# frozen_string_literal: true

source "https://rubygems.org"

gem "rack", "~> 3.1"
gem "rackup", "~> 2.2"
gem "thor", "~> 1.3"
gem "webrick", "~> 1.9"

# Клиент Claude нужен только смысловому классификатору, а он — работа на пробу и
# лежит вне репозитория. Гем остаётся объявленным: без него `require "anthropic"`
# не прошёл бы даже там, где файлы классификатора есть. Нет файлов — гем просто не
# используется, на сборку это не влияет.
group :classifiers do
  gem "anthropic", "~> 1.69"
end

group :development, :test do
  gem "rake", "~> 13.1"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.66"
  gem "rubocop-rspec", "~> 3.0"
  gem "webmock", "~> 3.24"
end
