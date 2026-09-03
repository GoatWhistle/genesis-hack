# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

# `rake` без аргументов — то, что должно быть зелёным перед каждым вливанием
# в main: сначала тесты, потом линтер.
task default: %i[spec rubocop]
