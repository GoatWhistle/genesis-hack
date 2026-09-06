# frozen_string_literal: true

module Service
  module AdapterBuilder
    module Analysis
      # Схема авторизации: первая у операции создания, остальные — в отчёт.
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

        # @param rules [Ports::Rules] заготовки авторизации профиля контракта
        def initialize(rules)
          @rules = rules
        end

        # @param spec [Models::ApiSpec] описание с объявленными схемами авторизации
        # @param operation [Models::ApiOperation, nil] операция создания: её порядок схем главный
        # @return [Plan] primary равен nil, если схемы в описании отсутствуют
        def call(spec, operation)
          schemes = spec.security_schemes.map { |scheme| build(scheme) }
          return missing if schemes.empty?

          ordered = order(schemes, operation)
          Plan.new(primary: ordered.first, alternatives: ordered.drop(1), notes: notes(ordered),
                   **printed(ordered.first))
        end

        private

        # @param scheme [Models::ApiSpec::SecurityScheme]
        # @return [Scheme] вид подписи и место её размещения
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

        # @return [Plan] для описания без объявленных схем
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
        # @return [Symbol] ключ заготовки: заголовок или строка запроса
        def api_key_key(scheme)
          scheme.location == QUERY ? :api_key_query : :api_key_header
        end

        # Ключ в строке запроса печатается при сборке адреса, поэтому отдаётся отдельно.
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
        # @return [String] заготовка с подставленными значениями
        def template(key, scheme)
          format(@rules.auth_template(key).to_s,
                 parameter: scheme.parameter, name: scheme.name, kind: scheme.kind)
        end

        # Порядок схем у операции важнее порядка объявления.
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
        # @return [Array(Integer, String)] ключ сортировки; имя обеспечивает устойчивый порядок
        def position(scheme, preferred)
          [preferred.index(scheme.name) || preferred.size, scheme.name]
        end

        # @param ordered [Array<Scheme>]
        # @return [Array<String>] пустой список, если схема одна
        def notes(ordered)
          return [] if ordered.size < 2

          ["провайдер принимает несколько схем авторизации: #{ordered.map(&:name).join(", ")}"]
        end
      end
    end
  end
end
