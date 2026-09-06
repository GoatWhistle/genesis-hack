# frozen_string_literal: true

# Подставные внешние сервисы смысловых классификаторов. Сети в проверках нет:
# и векторизатор, и Claude отвечают заготовленным, поэтому проверяется наша
# логика — раздача ролей, — а не чужая доступность.

# Векторизатор, который отдаёт заранее заготовленные векторы. Порядок известен:
# классификатор просит сначала эталоны ролей, за ними описания операций.
class StubEmbedder
  include Service::AdapterBuilder::Ports::Embedder

  # Единичный вектор под углом: так близость двух текстов задаётся углом между
  # ними, а не подбором координат руками.
  # @param degrees [Numeric]
  # @return [Array<Float>]
  def self.at(degrees)
    radians = degrees * Math::PI / 180
    [Math.cos(radians), Math.sin(radians)]
  end

  # @param vectors [Array<Array<Float>>] что вернуть, в порядке запроса
  def initialize(vectors)
    @vectors = vectors
  end

  # @return [Array<Array<Float>>]
  def embed(_texts) = @vectors

  # @return [String]
  def to_s = "подставной векторизатор"
end

# Claude, который отвечает заготовленным сообщением. Заодно запоминает запрос —
# по нему видно, что именно ушло модели.
class StubClaude
  Block = Struct.new(:type, :input, :text)
  Message = Struct.new(:content, :stop_reason)

  attr_reader :asked

  # @param assignments [Array<Hash>] разметка, которую модель «вернула»
  # @return [StubClaude] ответ вызовом инструмента
  def self.assigning(*assignments)
    new(Block.new(:tool_use, { assignments: assignments }))
  end

  # @return [StubClaude] ответ прозой: инструмент модель не вызвала
  def self.talking
    new(Block.new(:text, nil, "не понял вопроса"), stop_reason: "end_turn")
  end

  # @param blocks [Array<Block>] содержимое ответа
  # @param stop_reason [String]
  def initialize(*blocks, stop_reason: "tool_use")
    @message = Message.new(blocks, stop_reason)
  end

  # Клиент Anthropic адресуется как client.messages.create — обе ступени здесь
  # один и тот же объект.
  # @return [StubClaude]
  def messages = self

  # @return [Message]
  def create(**options)
    @asked = options
    @message
  end
end
