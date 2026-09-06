# frozen_string_literal: true

# Точка входа для rackup и других серверов приложений:
#   bundle exec rackup            — эквивалент bin/rsocket serve
require_relative "app/boot"

run Rsocket.api
