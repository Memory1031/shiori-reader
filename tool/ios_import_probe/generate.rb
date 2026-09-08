# Generates only an ignored test project. Requires the local xcodeproj gem.
require 'xcodeproj'
require 'fileutils'
root = File.expand_path('../..', __dir__)
output = File.join(root, '.tooling', 'ios-import-probe')
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'ImportProbe.xcodeproj'))
app = project.new_target(:application, 'ImportFixture', :ios, '15.0')
test = project.new_target(:ui_test_bundle, 'IntakeUITests', :ios, '15.0')
test.add_dependency(app)
[[app, 'FixtureApp.swift'], [test, 'IntakeUITests.swift']].each do |target, file|
  reference = project.main_group.new_file(File.join(__dir__, file))
  target.source_build_phase.add_file_reference(reference)
  target.build_configurations.each do |config|
    config.build_settings.merge!({
      'PRODUCT_NAME' => '$(TARGET_NAME)', 'SWIFT_VERSION' => '5.0',
      'GENERATE_INFOPLIST_FILE' => 'YES', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'CODE_SIGNING_ALLOWED' => 'NO', 'CURRENT_PROJECT_VERSION' => '1',
      'MARKETING_VERSION' => '1.0', 'IPHONEOS_DEPLOYMENT_TARGET' => '15.0'
    })
  end
end
app.build_configurations.each { |c| c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.shiori.importfixture' }
test.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.shiori.importfixture.uitests'
  c.build_settings['TEST_TARGET_NAME'] = 'ImportFixture'
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_test_target(test)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'ImportFixture', true)
