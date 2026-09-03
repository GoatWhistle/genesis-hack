# frozen_string_literal: true

require "yaml"

require_relative "errors"

module Rsocket
  # Доступ к словарям.
  #
  # Правило проекта: логика в коде, знания в словарях. Всё, что можно назвать
  # списком слов — названия ролей, статусы, коды ошибок, имена полей, веса
  # признаков, — лежит в YAML рядом с этим файлом и правится без единой строки
  # Ruby. Здесь только чтение и кэш: словари неизменны в пределах прогона.
  class Dictionaries
    DIR = File.join(__dir__, "dictionaries")

    # Имя файла = имя метода. Появится новый словарь — достаточно дописать его
    # сюда и положить файл рядом.
    FILES = %i[operations statuses errors money fields webhook weights].freeze

    # Общий экземпляр на прогон: файлы одни и те же, читать их по разу на
    # каждую операцию незачем.
    def self.default
      @default ||= new
    end

    def initialize(dir = DIR)
      @dir = dir
      @cache = {}
    end

    FILES.each do |name|
      define_method(name) { read(name) }
    end

    private

    def read(name)
      @cache[name] ||= load_file(name)
    end

    def load_file(name)
      path = File.join(@dir, "#{name}.yml")
      raise Rsocket::Error, "нет словаря #{name}.yml: искали в #{@dir}" unless File.file?(path)

      YAML.safe_load_file(path, aliases: true) || {}
    rescue Psych::SyntaxError => e
      raise Rsocket::Error, "словарь #{name}.yml не читается: #{e.message}"
    end
  end
end
