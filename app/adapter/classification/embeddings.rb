# frozen_string_literal: true

module Adapter
  # Классификаторы, которым для решения нужен внешний сервис. Тот, что работает
  # на правилах из конфига, живёт в сценарии сборки: он ничего не спрашивает.
  module Classification
    # Раздача ролей по смыслу текста. Роль и операция превращаются в слова
    # (Wording), слова — в векторы, а решение принимает косинусовая близость.
    #
    # Отличие от правил не только в способе счёта. Правила разбирают роли по
    # очереди из конфига, и первая забирает лучшее, что видит. Здесь порядок не
    # нужен: считается вся таблица «роль × операция», и пары разбираются по
    # убыванию близости — сначала самая уверенная во всём описании. Так отмена
    # выплаты не достаётся созданию только потому, что создание разбиралось
    # первым.
    #
    # Veto-правил здесь нет намеренно: смысл замера в том, чтобы понять, хватает
    # ли одной близости. Подпорки из правил сделали бы сравнение бессмысленным.
    class Embeddings
      include Service::AdapterBuilder::Ports::Classifier

      # Ниже этой близости пара считается случайной.
      #
      # Значение подобрано по examples/ и держится на узком окне: на этих четырёх
      # описаниях верным остаётся любой порог от 0.63 до 0.66. Узость не случайна —
      # Voyage сжимает всю шкалу в 0.57..0.87, и «совсем не похоже» у него выглядит
      # как 0.6. Порог поэтому вынесен в RSOCKET_EMBEDDING_THRESHOLD: на описании,
      # непохожем на наши примеры, его придётся двигать.
      DEFAULT_THRESHOLD = 0.65

      Match = Struct.new(:role, :operation, :score, keyword_init: true)

      # @param rules [Ports::Rules] роли контракта
      # @param embedder [Ports::Embedder] чем считаем векторы
      # @param threshold [Float] минимальная близость, ниже которой роль пустует
      def initialize(rules, embedder: Embedding::Voyage.new,
                     threshold: ENV.fetch("RSOCKET_EMBEDDING_THRESHOLD", DEFAULT_THRESHOLD).to_f)
        @rules = rules
        @embedder = embedder
        @threshold = threshold
      end

      # @param operations [Array<Models::ApiOperation>] все операции описания
      # @return [Hash{Symbol => Models::RoleBinding}] роль → привязка, включая заглушки
      def call(operations)
        roles = @rules.ordered_roles
        return roles.to_h { |role| [role.name, empty(role)] } if operations.empty?

        assign(roles, operations, closeness(roles, operations))
      end

      # @return [String] как классификатор называется в отчётах
      def to_s = "embeddings(#{@embedder})"

      private

      # @param roles [Array<Config::Settings::Role>]
      # @param operations [Array<Models::ApiOperation>]
      # @return [Hash{Symbol => Array<Float>}] роль → близость к каждой операции
      def closeness(roles, operations)
        vectors = embed(roles, operations)
        of_roles = vectors.first(roles.size)
        of_operations = vectors.last(operations.size)
        roles.each_with_index.to_h do |role, index|
          [role.name, of_operations.map { |vector| cosine(of_roles[index], vector) }]
        end
      end

      # Роли и операции уходят одной пачкой: это один запрос вместо двух и одна и
      # та же модель для обеих сторон сравнения.
      # @return [Array<Array<Float>>] векторы ролей, за ними векторы операций
      # @raise [RuntimeError] сервис вернул не столько векторов, сколько мы просили
      def embed(roles, operations)
        texts = roles.map { |role| wording.role(role) } +
                operations.map { |operation| wording.operation(operation) }
        vectors = @embedder.embed(texts)
        return vectors if vectors.size == texts.size

        raise "#{@embedder} вернул #{vectors.size} векторов вместо #{texts.size}"
      end

      # @param roles [Array<Config::Settings::Role>]
      # @param operations [Array<Models::ApiOperation>]
      # @param closeness [Hash{Symbol => Array<Float>}]
      # @return [Hash{Symbol => Models::RoleBinding}]
      def assign(roles, operations, closeness)
        bound = elect(ranked(roles, operations, closeness))
        roles.to_h { |role| [role.name, bound[role.name] || unbound(role, closeness, operations)] }
      end

      # Пары разбираются по убыванию близости: занятая роль и занятая операция
      # выбывают, а как только близость упала ниже порога — дальше смотреть нечего.
      # @param matches [Array<Match>]
      # @return [Hash{Symbol => Models::RoleBinding}] только занятые роли
      def elect(matches)
        bound = {}
        claimed = []
        matches.each do |match|
          next if bound.key?(match.role.name) || claimed.include?(match.operation)
          break if match.score < @threshold

          bound[match.role.name] = bind(match)
          claimed << match.operation
        end
        bound
      end

      # Ничьи решаются порядком ролей в конфиге и порядком операций в описании —
      # иначе результат зависел бы от порядка перебора.
      # @return [Array<Match>] все пары «роль × операция» по убыванию близости
      def ranked(roles, operations, closeness)
        pairs = roles.each_with_index.flat_map do |role, place|
          scores = closeness.fetch(role.name)
          operations.each_with_index.map do |operation, position|
            [Match.new(role: role, operation: operation, score: scores[position]), place, position]
          end
        end
        pairs.sort_by { |match, place, position| [-match.score, place, position] }.map(&:first)
      end

      # @param match [Match] выигравшая пара
      # @return [Models::RoleBinding]
      def bind(match)
        score = round(match.score)
        Models::RoleBinding.new(
          role: match.role, operation: match.operation, score: score, threshold: @threshold,
          reason: "близость #{score} при пороге #{@threshold}: " \
                  "описание операции похоже на эталон роли"
        )
      end

      # @param role [Config::Settings::Role]
      # @param closeness [Hash{Symbol => Array<Float>}]
      # @param operations [Array<Models::ApiOperation>]
      # @return [Models::RoleBinding] заглушка с ближайшим кандидатом в объяснении
      def unbound(role, closeness, operations)
        score, position = closeness.fetch(role.name).each_with_index.max_by(&:first)
        Models::RoleBinding.new(
          role: role, threshold: @threshold,
          reason: "ближайшая операция #{operations[position].method_name} набрала " \
                  "#{round(score)} при пороге #{@threshold}"
        )
      end

      # @param role [Config::Settings::Role]
      # @return [Models::RoleBinding]
      def empty(role)
        Models::RoleBinding.new(role: role, threshold: @threshold,
                                reason: "в описании нет ни одной операции")
      end

      # Косинус между векторами. Voyage отдаёт их уже нормированными, но делить на
      # длины всё равно нужно: порт допускает любую реализацию.
      # @return [Float] от -1 до 1
      def cosine(first, second)
        norm = Math.sqrt(first.sum { |value| value * value }) *
               Math.sqrt(second.sum { |value| value * value })
        return 0.0 if norm.zero?

        first.zip(second).sum { |left, right| left * right } / norm
      end

      # @return [Float] близость с точностью, которую имеет смысл читать глазами
      def round(value) = value.round(3)

      # @return [Module] словесное описание ролей и операций
      def wording = Service::AdapterBuilder::Classification::Wording
    end
  end
end
