# frozen_string_literal: true

# Заглушка вывода классификатора.
#
# Настоящий `Rsocket::Classify::Result` пишет другой участник, и на момент
# написания генератора его ещё нет. Ждать нельзя, поэтому генератор написан
# против описанной в docs/context/95-tasks.md формы, а здесь она собрана
# руками для трёх наших описаний.
#
# Это не подмена чужой работы: здесь нет ни одного признака, ни одной оценки и
# ни одного порога — только результат, который классификатор обязан выдать.
# Когда появится настоящий, заглушка выбрасывается, а генератор не меняется.
module ClassificationDouble
  RoleAssignment = Struct.new(:role, :operation, :score, :verdict, :evidence, keyword_init: true)
  StatusMapping = Struct.new(:provider_value, :canonical, :verdict, :evidence, keyword_init: true)
  ErrorMapping = Struct.new(:http_code, :provider_code, :klass, :evidence, keyword_init: true)
  MoneyDecision = Struct.new(:unit, :field_path, :evidence, keyword_init: true)
  WebhookInfo = Struct.new(:operation, :signature_header, :algorithm, :event_field, :status_field,
                           keyword_init: true)
  Result = Struct.new(:roles, :statuses, :errors, :money, :webhook, :notes, keyword_init: true)

  # Роли, статусы, ошибки и единицы суммы для каждого из трёх описаний.
  DATA = {
    "novapay" => {
      roles: { create_payout: "createPayout", fetch_status: "getPayoutStatus",
               cancel: "cancelPayout" },
      statuses: { "pending" => :created, "processing" => :processing, "completed" => :succeeded,
                  "failed" => :rejected, "cancelled" => :cancelled },
      errors: { 400 => ["validation_error", :validation], 401 => ["unauthorized", :auth],
                402 => ["insufficient_balance", :retryable], 404 => ["not_found", :final],
                409 => [nil, :final], 422 => ["validation_error", :validation],
                429 => ["rate_limit_exceeded", :limit], 500 => ["internal_error", :retryable] },
      money: [:minor, "amount"],
      webhook: { operation: "payoutWebhook", header: "X-NovaPay-Signature", event: "event",
                 status: "status" }
    },
    "swiftpay" => {
      roles: { create_payout: "submitTransfer", fetch_status: "fetchTransfer",
               cancel: "revokeTransfer" },
      statuses: { "new" => :created, "sent" => :processing, "paid" => :succeeded,
                  "declined" => :rejected },
      errors: { 400 => ["invalid_request", :validation], 401 => ["unauthenticated", :auth],
                404 => ["not_found", :final], 409 => ["conflict", :final] },
      money: [:decimal, "amount"],
      webhook: nil
    },
    "kassabox" => {
      roles: { create_payout: "makeTransfer", fetch_status: "transferInfo",
               cancel: "abortTransfer" },
      statuses: { "registered" => :created, "executing" => :processing,
                  "delivered" => :succeeded, "rejected" => :rejected, "aborted" => :cancelled },
      errors: { 400 => ["bad_request", :validation], 401 => ["forbidden", :auth],
                409 => ["conflict", :final] },
      money: [:minor, "sum.value"],
      webhook: nil
    }
  }.freeze

  def self.build(provider, spec)
    data = DATA.fetch(provider)
    Result.new(
      roles: roles(data, spec), statuses: statuses(data), errors: errors(data),
      money: money(data), webhook: webhook(data, spec), notes: []
    )
  end

  def self.roles(data, spec)
    data[:roles].to_h do |role, operation_id|
      [role, RoleAssignment.new(role: role, operation: find(spec, operation_id), score: 1.0,
                                verdict: :confident, evidence: [])]
    end
  end

  def self.statuses(data)
    data[:statuses].map do |value, canonical|
      StatusMapping.new(provider_value: value, canonical: canonical, verdict: :confident,
                        evidence: [])
    end
  end

  def self.errors(data)
    data[:errors].map do |code, (provider_code, klass)|
      ErrorMapping.new(http_code: code, provider_code: provider_code, klass: klass, evidence: [])
    end
  end

  def self.money(data)
    unit, path = data[:money]
    MoneyDecision.new(unit: unit, field_path: path, evidence: [])
  end

  def self.webhook(data, spec)
    info = data[:webhook]
    return nil if info.nil?

    WebhookInfo.new(operation: find(spec, info[:operation]), signature_header: info[:header],
                    algorithm: :hmac_sha256, event_field: info[:event],
                    status_field: info[:status])
  end

  def self.find(spec, operation_id)
    spec.operations.find { |operation| operation.operation_id == operation_id }
  end
end
