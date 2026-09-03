# frozen_string_literal: true

module Rsocket
  module Classify
    # Один признак: что сработало, почему и сколько это стоит.
    #
    # Мы принципиально не показываем человеку «уверенность 0.87». Показываем то,
    # что видели сами: «имя операции содержит create», «в теле есть сумма и
    # получатель». Инженер читает формулировку и решает, согласен ли он, — это
    # и есть наш ответ на вопрос «а если инструмент ошибётся».
    Evidence = Data.define(:signal, :detail, :weight) do
      def initialize(**attributes)
        defaults = { weight: 0.0 }
        super(**defaults.merge(attributes))
      end

      def to_s
        "#{detail} (#{signal}, вес #{format("%.1f", weight)})"
      end
    end
  end
end
