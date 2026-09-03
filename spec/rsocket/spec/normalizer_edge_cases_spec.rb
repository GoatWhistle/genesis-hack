# frozen_string_literal: true

require "tempfile"

require "spec_helper"

RSpec.describe Rsocket::Spec::Normalizer do
  def normalize_yaml(contents)
    Tempfile.create(["unusual_provider", ".yaml"]) do |file|
      file.write(contents)
      file.flush
      return described_class.normalize(Rsocket::Spec::Loader.load(file.path))
    end
  end

  def normalization_error(contents)
    normalize_yaml(contents)
    raise "Expected normalization to fail"
  rescue Rsocket::Error => e
    e
  end

  def unknown_auth_summary(result)
    scheme = result.security_schemes.first
    note = result.notes.find { |item| item.where.start_with?("components.securitySchemes") }
    [scheme.kind, scheme.description, note.level, note.where, note.message]
  end

  def alternative_auth_summary(result)
    schemes = result.security_schemes.map { |scheme| [scheme.id, scheme.kind] }
    [schemes, result.operations.first.security]
  end

  def expected_coverage_notes
    [
      coverage_note("Для операции не описано ни одного примера; мок соберёт ответ по схеме"),
      coverage_note(
        "Для операции не описаны ответы с ошибками; " \
        "обработку отказов нужно проверить вручную"
      )
    ]
  end

  def coverage_note(message)
    { level: :needs_confirmation, where: "paths./transfers.post.responses", message: message }
  end

  def no_operations_yaml
    <<~YAML
      openapi: 3.1.0
      info: { title: No operations, version: 1.0.0 }
      paths:
        /transfers/{id}:
          parameters:
            - in: path
              name: id
              required: true
              schema: { type: string }
    YAML
  end

  def unknown_auth_yaml
    <<~YAML
      openapi: 3.1.0
      info: { title: Custom auth, version: 1.0.0 }
      paths:
        /transfers:
          get:
            responses:
              '200': { description: ok }
      components:
        securitySchemes:
          SignedRequest:
            type: customSignature
            description: Provider-specific signing
      security:
        - SignedRequest: []
    YAML
  end

  def no_examples_or_errors_yaml
    <<~YAML
      openapi: 3.0.3
      info: { title: Sparse API, version: 1.0.0 }
      paths:
        /transfers:
          post:
            requestBody:
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      amount: { type: number, minimum: 0.01 }
            responses:
              '200':
                description: accepted
                content:
                  application/json:
                    schema:
                      type: object
                      properties:
                        id: { type: string }
    YAML
  end

  def query_only_input_yaml
    <<~YAML
      openapi: 3.0.3
      info: { title: Query input, version: 1.0.0 }
      paths:
        /transfers:
          post:
            parameters:
              - in: query
                name: amount
                required: true
                schema: { type: number, minimum: 0.01 }
              - in: query
                name: recipient
                required: true
                schema: { type: string }
            responses:
              '202': { description: queued }
    YAML
  end

  def alternative_auth_yaml
    <<~YAML
      openapi: 3.1.0
      info: { title: Alternative auth, version: 1.0.0 }
      paths:
        /transfers:
          get:
            responses:
              '200': { description: ok }
      components:
        securitySchemes:
          HeaderKey:
            type: apiKey
            in: header
            name: X-Access-Key
          BearerToken:
            type: http
            scheme: bearer
      security:
        - HeaderKey: []
        - BearerToken: []
    YAML
  end

  it "reports a paths section that has parameters but no HTTP methods" do
    error = normalization_error(no_operations_yaml)
    expect([error.class, error.where, error.message.lines.size])
      .to eq([Rsocket::SpecError, "paths", 1])
  end

  it "preserves an unknown authentication scheme and explains it in a note" do
    result = normalize_yaml(unknown_auth_yaml)
    expect(unknown_auth_summary(result))
      .to eq([:unknown, "Provider-specific signing", :needs_confirmation,
              "components.securitySchemes.SignedRequest",
              "Способ авторизации не распознан и требует ручной проверки"])
  end

  it "accepts an operation with neither examples nor documented errors" do
    operation = normalize_yaml(no_examples_or_errors_yaml).operations.first
    actual = [operation.request_examples, operation.responses.keys,
              operation.responses.fetch(200).examples]
    expect(actual).to eq([{}, [200], {}])
  end

  it "explains missing examples and documented errors" do
    notes = normalize_yaml(no_examples_or_errors_yaml).notes.map(&:to_h)

    expect(notes).to match_array(expected_coverage_notes)
  end

  it "keeps query-only input separate from a missing request body" do
    operation = normalize_yaml(query_only_input_yaml).operations.first
    actual = [operation.query_params.map(&:name), operation.query_params.map(&:required),
              operation.request_fields]
    expect(actual).to eq([%w[amount recipient], [true, true], []])
  end

  it "retains both alternative authentication schemes" do
    result = normalize_yaml(alternative_auth_yaml)
    expect(alternative_auth_summary(result)).to eq(
      [[["HeaderKey", :api_key], ["BearerToken", :bearer]], %w[HeaderKey BearerToken]]
    )
  end
end
