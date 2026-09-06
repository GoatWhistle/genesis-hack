# frozen_string_literal: true

require "yaml"

module Service
  module AdapterBuilder
    module Rendering
      # Отчёт о сборке: какой эндпоинт провайдера какой роли достался, по какому
      # правилу и с каким счётом. Нужен, чтобы решение инструмента можно было
      # проверить глазами и поправить правила, а не сгенерированный код.
      class Report
        HEADER = <<~TEXT
          # Что инструмент понял про API провайдера. Файл читается человеком: если роль
          # назначена неверно, правьте правила профиля контракта и пересоберите.
        TEXT

        # @param blueprint [Models::Blueprint] всё, что инструмент решил
        # @param spec [Models::ApiSpec] разобранное описание
        # @param reference [String, Pathname] откуда описание взято
        def initialize(blueprint, spec, reference)
          @blueprint = blueprint
          @spec = spec
          @reference = reference
        end

        # @return [Hash{String => Object}] отчёт целиком; ключи строками — уходит в YAML
        def to_h
          source.merge(
            "roles" => roles, "statuses" => @blueprint.status_map, "events" => @blueprint.event_map,
            "amount" => amount, "conditions" => conditions, "callback" => callback,
            "auth" => auth, "warnings" => @blueprint.warnings
          )
        end

        # Отчёт — такой же выходной файл, как остальные, и уходит тем же путём.
        # @return [String] отчёт в YAML с шапкой для человека
        def to_yaml = HEADER + to_h.to_yaml.sub("---\n", "")

        private

        # @return [Hash] по какому описанию, под какой контракт и для кого собрано
        def source
          {
            "provider" => @blueprint.provider,
            "contract" => @blueprint.contract,
            "spec" => @reference.to_s,
            "api" => "#{@spec.title} #{@spec.version}".strip,
            "base_url" => @blueprint.base_url
          }
        end

        # @return [Hash] роль → как она разобрана
        def roles
          @blueprint.bindings.to_h do |name, binding|
            [name.to_s,
             if binding.bound?
               bound(binding)
             else
               { "status" => "заглушка",
                 "why" => binding.explanation }
             end]
          end
        end

        # @param binding [Models::RoleBinding] роль, которой нашлась операция
        # @return [Hash] эндпоинт, имя операции, счёт, порог и сработавшие правила
        def bound(binding)
          {
            "status" => state(binding.role),
            "operation" => binding.operation.method_name,
            "endpoint" => binding.endpoint,
            "score" => binding.score,
            "threshold" => binding.role.threshold,
            "matched_rules" => binding.matched_rules.map(&:to_s)
          }
        end

        # Роль, принимающая уведомление, к провайдеру не ходит: её эндпоинт описывает
        # запрос, который придёт к нам. В отчёте это разные вещи.
        # @param role [Config::Settings::Role] роль контракта
        # @return [String] что происходит по этому эндпоинту
        def state(role)
          role.trait?(:receives_callback) ? "входящее уведомление" : "запрос к провайдеру"
        end

        # @return [Hash] в каких единицах уходит сумма
        def amount
          minor = @blueprint.amount_multiplier != 1
          { "multiplier" => @blueprint.amount_multiplier,
            "note" => minor ? "сумма уходит в копейках" : "сумма уходит в валюте" }
        end

        # @return [Array<Hash>] предпроверки вместе с источником каждой
        def conditions
          @blueprint.constraints.map do |constraint|
            { "code" => constraint.code, "kind" => constraint.kind.to_s,
              "checks" => constraint.subject, "value" => constraint.value,
              "source" => constraint.source }
          end
        end

        # @return [Hash] описан ли webhook и чем он подписан
        def callback
          return { "supported" => false } unless @blueprint.callback.supported

          { "supported" => true, "signature_header" => @blueprint.callback.signature_header,
            "algorithm" => @blueprint.callback.signature_algorithm,
            "operation_id_field" => Array(@blueprint.callback.operation_path).join(".") }
        end

        # @return [Hash] выбранная схема авторизации и её альтернативы
        def auth
          plan = @blueprint.credentials
          { "primary" => plan.primary && "#{plan.primary.name} (#{plan.primary.kind})",
            "alternatives" => plan.alternatives.map(&:name), "notes" => plan.notes }
        end
      end
    end
  end
end
