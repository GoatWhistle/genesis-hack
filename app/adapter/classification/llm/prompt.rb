# frozen_string_literal: true

module Adapter
  module Classification
    class Llm
      # Как задача объясняется модели: инструкция, схема ответа и сам вопрос.
      # Вынесено из классификатора намеренно — здесь меняют формулировки, а там
      # ходят в сеть и разбирают ответ.
      module Prompt
        # Ни одна операция не подошла — про это модель говорит нулём.
        NONE = 0

        # Схема разметки. Инструмент нужен не ради действия, а ради формы ответа:
        # прозу пришлось бы разбирать регулярками, а это ровно то, от чего мы
        # здесь уходим.
        TOOL = {
          name: "assign_roles",
          description: "Отдать разметку: какой роли контракта какая операция описания",
          input_schema: {
            type: "object",
            additionalProperties: false,
            required: ["assignments"],
            properties: {
              assignments: {
                type: "array",
                description: "по одной записи на каждую роль из списка",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: %w[role operation confidence reason],
                  properties: {
                    role: { type: "string", description: "имя роли из списка ролей" },
                    operation: { type: "integer",
                                 description: "номер операции; #{NONE} — подходящей нет" },
                    confidence: { type: "number", description: "уверенность в этой паре, 0..1" },
                    reason: { type: "string", description: "одна короткая фраза по-русски" }
                  }
                }
              }
            }
          }
        }.freeze

        INSTRUCTION = <<~TEXT.freeze
          Ты раскладываешь операции платёжного API по ролям контракта интеграции.
          Ответ отдавай единственным вызовом инструмента assign_roles, без текста вокруг.

          Как решать:
          - про каждую роль из списка ровно одна запись, отвергнутые варианты не перечисляй;
          - одна операция достаётся не больше чем одной роли;
          - роли, которой не нашлось операции, ставь operation = #{NONE}: пустая роль честнее неверной;
          - служебные операции — баланс, справочники, курсы, возвраты — ролей не занимают;
          - создание выплаты, её отмена и возврат средств — разные вещи, даже если названы похоже;
          - confidence — насколько ты уверен именно в этой паре, от 0 до 1.
        TEXT

        module_function

        # @param roles [Array<Config::Settings::Role>]
        # @param operations [Array<Models::ApiOperation>]
        # @return [String] два пронумерованных списка: номером роль и операция и адресуются
        def question(roles, operations)
          "Роли контракта:\n#{listing(roles) { |role| role_line(role) }}\n\n" \
            "Операции описания:\n#{listing(operations) { |item| wording.operation(item) }}"
        end

        # @return [String]
        def listing(items)
          items.each_with_index.map { |item, index| "#{index + 1}. #{yield(item)}" }.join("\n")
        end

        # @param role [Config::Settings::Role]
        # @return [String] имя роли, её название и чем она занята в сценарии
        def role_line(role)
          [role.name, role.title, wording.traits(role)].compact.join(" — ")
        end

        # @return [Module] словесное описание ролей и операций
        def wording = Service::AdapterBuilder::Classification::Wording
      end
    end
  end
end
