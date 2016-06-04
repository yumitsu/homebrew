# vim: filetype=ruby

SimpleCov.start do
  tests_path = File.dirname(__FILE__)

  minimum_coverage 40
  coverage_dir File.expand_path("#{tests_path}/coverage")
  root File.expand_path("#{tests_path}/../../")

  add_filter "Formula/"
  add_filter "Homebrew/compat/"
  add_filter "Homebrew/test/"
  add_filter "Homebrew/vendor/"
  add_filter "Taps/"

  # Not using this during integration tests makes the tests 4x times faster
  # without changing the coverage.
  unless ENV["HOMEBREW_INTEGRATION_TEST"]
    track_files "#{SimpleCov.root}/**/*.rb"
  end

  # Add groups and the proper project name to the output.
  project_name "Homebrew"
  add_group "Commands", %w[/Homebrew/cmd/ /Homebrew/dev-cmd/]
  add_group "Extensions", "/Homebrew/extend/"
  add_group "OS", "/Homebrew/os/"
  add_group "Requirements", "/Homebrew/requirements/"
  add_group "Scripts", %w[
    /brew.rb
    /Homebrew/build.rb
    /Homebrew/postinstall.rb
    /Homebrew/test.rb
  ]
end

if ENV["HOMEBREW_INTEGRATION_TEST"]
  SimpleCov.command_name ENV["HOMEBREW_INTEGRATION_TEST"]
  SimpleCov.at_exit do
    exit_code = $!.nil? ? 0 : $!.status
    $stdout.reopen("/dev/null")
    SimpleCov.result # Just save result, but don't write formatted output.
    exit! exit_code
  end
end

# Don't use Coveralls outside of CI, as it will override SimpleCov's default
# formatter causing the `index.html` not to be written once all tests finish.
if RUBY_VERSION.split(".").first.to_i >= 2 && !ENV["HOMEBREW_INTEGRATION_TEST"] && ENV["CI"]
  require "coveralls"
  Coveralls.wear!
end
