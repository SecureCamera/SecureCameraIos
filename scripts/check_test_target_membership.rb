#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Fails if any .swift file under a test directory is NOT compiled by its test
# target. Guards against the silent "file on disk but not a target member" bug,
# where a test file never compiles and its tests never run (the test bundle
# reports success while executing nothing).
#
# Run locally:   bundle exec ruby scripts/check_test_target_membership.rb
# Runs in CI via the fastlane `test` lane.

require "xcodeproj"
require "set"
require "pathname"

REPO_ROOT = File.expand_path(File.join(__dir__, ".."))
PROJECT_PATH = File.join(REPO_ROOT, "SnapSafe.xcodeproj")

# directory (relative to repo root) => target that must compile every .swift in it
MAPPING = {
  "SnapSafeTests" => "SnapSafeTests"
}.freeze

project = Xcodeproj::Project.open(PROJECT_PATH)
failures = []

MAPPING.each do |dir, target_name|
  target = project.targets.find { |t| t.name == target_name }
  abort "ERROR: target '#{target_name}' not found in #{PROJECT_PATH}" if target.nil?

  # Files the target actually compiles: explicit Sources build phase, plus any
  # Xcode 16 file-system-synchronized groups (which auto-include their folders).
  compiled = Set.new
  target.source_build_phase.files.each do |build_file|
    ref = build_file.file_ref
    compiled << File.expand_path(ref.real_path.to_s) if ref
  end
  if target.respond_to?(:file_system_synchronized_groups)
    Array(target.file_system_synchronized_groups).each do |group|
      base = group.real_path.to_s
      Dir.glob(File.join(base, "**", "*.swift")).each { |f| compiled << File.expand_path(f) }
    end
  end

  # Every .swift file on disk under the directory.
  disk = Dir.glob(File.join(REPO_ROOT, dir, "**", "*.swift")).map { |f| File.expand_path(f) }

  disk.reject { |f| compiled.include?(f) }.sort.each do |f|
    rel = Pathname.new(f).relative_path_from(Pathname.new(REPO_ROOT)).to_s
    failures << "#{rel}  (not a member of target '#{target_name}')"
  end
end

if failures.empty?
  puts "✓ Test target membership: every test source file is compiled by its target."
  exit 0
end

warn "✗ Test target membership check FAILED."
warn "  These .swift files exist on disk but are not compiled, so their tests never run:"
failures.each { |m| warn "    - #{m}" }
warn ""
warn "  Add each file to its test target (Xcode: File Inspector > Target Membership,"
warn "  or via the xcodeproj gem), then re-run."
exit 1
