# frozen_string_literal: true

# Общий доступ к описаниям из examples/ для тестов разбора смысла.
#
# Все три описания читаются по многу раз в разных файлах тестов, поэтому
# разобранный вид держится в памяти: это экономит секунды на каждом прогоне и
# гарантирует, что тесты сравнивают один и тот же объект.
module ExampleSpecs
  def self.cache
    @cache ||= {}
  end

  def ir(name)
    ExampleSpecs.cache[name] ||=
      Rsocket::Spec::Normalizer.normalize(Rsocket::Spec::Loader.load(spec_path(name)))
  end

  def spec_path(name)
    File.join(Rsocket.root, "examples", name, "provider_api.yaml")
  end

  def classify_context(name, dictionaries: Rsocket::Dictionaries.default)
    Rsocket::Classify::Context.new(
      spec: ir(name), dictionaries: dictionaries,
      roles: Rsocket::Classify::Roles.default(dictionaries)
    )
  end

  def operation(name, operation_id)
    ir(name).operations.find { |item| item.operation_id == operation_id }
  end
end

RSpec.configure { |config| config.include ExampleSpecs }
