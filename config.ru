# frozen_string_literal: true

# Точка входа для rackup и любого другого сервера приложений:
#   bundle exec rackup            — то же самое, что и bin/rsocket serve
require_relative "app/boot"

run Rsocket.api
