# frozen_string_literal: true

module Rsocket
  module Report
    # Печать отчёта человеку.
    #
    # Порядок разделов выбран не по важности находок, а по тому, что человеку
    # делать дальше: сначала что готово, потом что проверить, потом чего мы не
    # умеем. Последние два раздела печатаются, даже когда они пусты, — «ничего
    # не требует подтверждения» это тоже сообщение, и его отсутствие читается
    # как умолчание о проблемах.
    class Terminal
      HEADINGS = {
        confident: "Понято уверенно", needs_confirmation: "Требует подтверждения",
        unsupported: "Не поддержано"
      }.freeze

      def initialize(report, output: $stdout)
        @report = report
        @output = output
      end

      def print
        sections = @report.sections
        heading
        HEADINGS.each_key { |name| section(name, sections.public_send(name)) }
        @output
      end

      private

      def heading
        line("Описание: #{@report.title}")
        line(@report.summary.capitalize)
      end

      def section(name, findings)
        line("")
        line("#{HEADINGS[name]} (#{findings.size})")
        line("  ничего") if findings.empty?
        findings.each { |finding| finding(finding) }
      end

      def finding(finding)
        line("  - #{finding.title}")
        finding.details.each { |detail| line("      #{detail}") }
      end

      def line(text) = @output.puts(text)
    end
  end
end
