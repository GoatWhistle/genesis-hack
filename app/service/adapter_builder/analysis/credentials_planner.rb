# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Чем сервис подписывает запросы. Провайдер может предложить несколько
      # равноправных схем — берём ту, что первой указана у операции создания,
      # остальные уходят в отчёт как альтернативы.
      #
      # Здесь же схема превращается в строки контракта: как именно подписывается
      # запрос, знает только контракт, и его заготовки лежат в его же конфиге.
      # Шаблону остаётся их напечатать.
      class CredentialsPlanner
        Plan = Struct.new(:primary, :alternatives, :lines, :query_pair, :comment, :notes,
                          keyword_init: true)
        Scheme = Struct.new(:name, :kind, :parameter, :location, :credentials,
                            keyword_init: true)

        NO_SCHEMES = "в описании нет securitySchemes — авторизацию придётся дописать руками"
        QUERY = "query"

        CREDENTIAL_NAMES = {
          api_key: %w[api_key], bearer: %w[access_token], basic: %w[username
                                                                    password], unsupported: []
        }.freeze

        # @param rules [Ports::Rules] заготовки авторизации из профиля контракта
        def initialize(rules)
          @rules = rules
        end

        # @param spec [Models::ApiSpec] описание с объявленными схемами авторизации
        # @param operation [Models::ApiOperation, nil] операция создания — её порядок главный
        # @return [Plan] primary равен nil, если схем в описании нет вовсе
        def call(spec, operation)
          schemes = spec.security_schemes.map { |scheme| build(scheme) }
          return missing if schemes.empty?

          ordered = order(schemes, operation)
          Plan.new(primary: ordered.first, alternatives: ordered.drop(1), notes: notes(ordered),
                   **printed(ordered.first))
        end

        private

        # @param scheme [Models::ApiSpec::SecurityScheme]
        # @return [Scheme] чем и куда подписывать запрос
        def build(scheme)
          kind = scheme.credential_kind
          Scheme.new(name: scheme.name, kind: kind, parameter: scheme.parameter || scheme.name,
                     location: (scheme.location || "header").to_s,
                     credentials: CREDENTIAL_NAMES.fetch(kind))
        end

        # @param scheme [Scheme] выбранная схема
        # @return [Hash] готовые строки для шаблона
        def printed(scheme)
          { lines: lines(scheme), query_pair: query_pair(scheme), comment: [comment(scheme)] }
        end

        # @return [Plan] когда описание не объявило ни одной схемы
        def missing
          Plan.new(alternatives: [], notes: [NO_SCHEMES], query_pair: nil,
                   lines: [@rules.auth_template(:missing)],
                   comment: [@rules.auth_template(:comment_missing)])
        end

        # @param scheme [Scheme]
        # @return [Array<String>] строки тела метода, подписывающего запрос
        def lines(scheme)
          case scheme.kind
          when :api_key then [template(api_key_key(scheme), scheme)]
          when :bearer, :basic then [template(scheme.kind, scheme)]
          else [template(:unsupported, scheme)]
          end
        end

        # @param scheme [Scheme]
        # @return [Symbol] ключ заготовки: ключ уходит заголовком или в строке запроса
        def api_key_key(scheme)
          scheme.location == QUERY ? :api_key_query : :api_key_header
        end

        # Ключ в строке запроса печатается не там, где подписываются заголовки,
        # а рядом со сборкой адреса — поэтому он отдаётся шаблону отдельно.
        # @param scheme [Scheme]
        # @return [String, nil]
        def query_pair(scheme)
          return nil unless scheme.kind == :api_key && scheme.location == QUERY

          template(:query_pair, scheme)
        end

        # @param scheme [Scheme]
        # @return [String] строка комментария над методом авторизации
        def comment(scheme)
          template(:comment, scheme)
        end

        # @param key [Symbol] какая заготовка контракта нужна
        # @param scheme [Scheme] имена из описания провайдера
        # @return [String] заготовка с подставленными именами
        def template(key, scheme)
          format(@rules.auth_template(key).to_s,
                 parameter: scheme.parameter, name: scheme.name, kind: scheme.kind)
        end

        # Порядок из операции важнее порядка объявления: у KassaBox ключ и Basic
        # объявлены рядом, а выбирает провайдер тот, что указан у метода.
        # @param schemes [Array<Scheme>]
        # @param operation [Models::ApiOperation, nil]
        # @return [Array<Scheme>] сначала та, которой сервис подписывает запросы
        def order(schemes, operation)
          preferred = Array(operation&.security).flat_map(&:keys).map(&:to_s)
          supported = schemes.reject { |scheme| scheme.kind == :unsupported }
          supported = schemes if supported.empty?
          supported.sort_by { |scheme| position(scheme, preferred) }
        end

        # @param scheme [Scheme]
        # @param preferred [Array<String>] имена схем в порядке из операции
        # @return [Array(Integer, String)] ключ сортировки; имя добавлено ради устойчивости
        def position(scheme, preferred)
          [preferred.index(scheme.name) || preferred.size, scheme.name]
        end

        # @param ordered [Array<Scheme>]
        # @return [Array<String>] пусто, если выбирать было не из чего
        def notes(ordered)
          return [] if ordered.size < 2

          ["провайдер принимает несколько схем авторизации: #{ordered.map(&:name).join(", ")}"]
        end
      end
    end
  end
end
