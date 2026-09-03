# frozen_string_literal: true

require "psych"

require_relative "../errors"

module Rsocket
  module Spec
    LoaderResult = Data.define(:document, :raw_document, :notes)
    LoaderNote = Data.define(:level, :where, :message)

    # Reads a YAML OpenAPI document and returns both its source and resolved forms.
    class Loader
      DEFAULT_MAX_REFERENCE_DEPTH = 64
      Result = LoaderResult
      Note = LoaderNote

      def self.load(path, max_reference_depth: DEFAULT_MAX_REFERENCE_DEPTH)
        new(path, max_reference_depth:).call
      end

      def initialize(path, max_reference_depth: DEFAULT_MAX_REFERENCE_DEPTH)
        @path = path.to_s
        @max_reference_depth = max_reference_depth
      end

      def call
        raw_document = parse(read_source)
        validate(raw_document)
        resolver = ReferenceResolver.new(raw_document, max_depth: @max_reference_depth)

        Result.new(
          document: resolver.call,
          raw_document: TreeCopier.new.call(raw_document),
          notes: resolver.notes.freeze
        )
      end

      private

      def read_source
        File.read(@path)
      rescue Errno::ENOENT
        raise SpecError, "Не удалось прочитать описание API: файл не найден — #{@path}"
      rescue Errno::EACCES
        raise SpecError, "Не удалось прочитать описание API: нет прав на чтение — #{@path}"
      rescue SystemCallError => e
        raise SpecError, "Не удалось прочитать описание API #{@path}: #{e.message}"
      end

      def parse(source)
        raise SpecError, "Описание API пустое (#{@path})" if source.strip.empty?

        Psych.safe_load(source, aliases: true, filename: @path)
      rescue Psych::SyntaxError => e
        where = "строка #{e.line}, столбец #{e.column}"
        raise SpecError.new("Не удалось разобрать YAML: #{e.problem}", where:)
      rescue Psych::DisallowedClass => e
        raise SpecError, "Описание API содержит небезопасный тип YAML: #{e.message}"
      end

      def validate(document)
        raise SpecError, "Описание API пустое (#{@path})" if document.nil?

        unless document.is_a?(Hash)
          raise SpecError, "Описание API должно быть YAML-объектом (#{@path})"
        end
        unless document.key?("paths")
          raise SpecError, "В описании API нет обязательного раздела paths (#{@path})"
        end
        return if document["paths"].is_a?(Hash)

        raise SpecError.new("Раздел paths должен быть объектом", where: "paths")
      end
    end

    # Resolves local JSON References while retaining unsupported external ones.
    class ReferenceResolver
      Context = Data.define(:where, :reference_stack, :ancestors)

      attr_reader :notes

      def initialize(root, max_depth:)
        @root = root
        @max_depth = max_depth
        @pointer = JsonPointer.new(root)
        @notes = []
        @composition = SchemaComposition.new(method(:resolve), @notes)
      end

      def call
        resolve(@root, Context.new(where: "", reference_stack: [], ancestors: []))
      end

      private

      def resolve(node, context)
        case node
        when Hash then resolve_hash(node, enter(node, context))
        when Array then resolve_array(node, enter(node, context))
        when String then node.dup
        else node
        end
      end

      def resolve_hash(hash, context)
        return resolve_reference(hash, context) if hash.key?("$ref")

        compositions = hash.slice("allOf", "oneOf", "anyOf")
        ordinary = hash.except(*compositions.keys)
        base = resolve_entries(ordinary, context)
        @composition.call(base, compositions, context)
      end

      def resolve_reference(hash, context)
        reference = hash.fetch("$ref")
        return resolve_external(hash, reference, context) unless local_reference?(reference)

        check_reference!(reference, context)
        target = @pointer.follow(reference, at: display_where(context.where))
        target_context = Context.new(
          where: context.where,
          reference_stack: context.reference_stack + [reference],
          ancestors: []
        )
        SchemaMerger.call(resolve(target, target_context), resolve(hash.except("$ref"), context))
      end

      def resolve_external(hash, reference, context)
        @notes << NoteFactory.call(
          level: :unsupported,
          where: Locations.child(context.where, "$ref"),
          message: "Внешняя ссылка #{reference.inspect} не поддерживается и оставлена без изменений"
        )
        resolve_entries(hash, context)
      end

      def resolve_entries(hash, context)
        hash.to_h do |key, value|
          child_context = context.with(where: Locations.child(context.where, key))
          [key.dup, resolve(value, child_context)]
        end
      end

      def resolve_array(array, context)
        array.each_with_index.map do |value, index|
          child_context = context.with(where: Locations.child(context.where, "[#{index}]"))
          resolve(value, child_context)
        end
      end

      def enter(node, context)
        if context.ancestors.include?(node.object_id)
          where = display_where(context.where)
          raise SpecError.new("Обнаружена кольцевая структура YAML", where:)
        end

        context.with(ancestors: context.ancestors + [node.object_id])
      end

      def check_reference!(reference, context)
        if context.reference_stack.include?(reference)
          chain = (context.reference_stack + [reference]).join(" -> ")
          message = "Обнаружена кольцевая локальная ссылка: #{chain}"
          raise ReferenceError.new(message, where: display_where(context.where))
        end
        return if context.reference_stack.length < @max_depth

        message = "Превышена максимальная глубина локальных ссылок (#{@max_depth})"
        raise ReferenceError.new(message, where: display_where(context.where))
      end

      def local_reference?(reference)
        reference.is_a?(String) && reference.start_with?("#")
      end

      def display_where(where)
        where.empty? ? "корень документа" : where
      end
    end

    # Applies the schema-composition rules intentionally supported by the loader.
    class SchemaComposition
      def initialize(resolver, notes)
        @resolver = resolver
        @notes = notes
      end

      def call(base, compositions, context)
        merged = merge_all_of(base, compositions["allOf"], context)
        merged = merge_choice(merged, "oneOf", compositions["oneOf"], context)
        merge_choice(merged, "anyOf", compositions["anyOf"], context)
      end

      private

      def merge_all_of(base, branches, context)
        return base unless branches

        validate_branches!("allOf", branches, context, allow_empty: true)
        branches.each_with_index.reduce(base) do |merged, (branch, index)|
          SchemaMerger.call(merged, resolve_branch(branch, "allOf", index, context))
        end
      end

      def merge_choice(base, keyword, branches, context)
        return base unless branches

        validate_branches!(keyword, branches, context, allow_empty: false)
        choice_where = Locations.child(context.where, keyword)
        @notes << choice_note(keyword, choice_where)
        SchemaMerger.call(base, resolve_branch(branches.first, keyword, 0, context))
      end

      def resolve_branch(branch, keyword, index, context)
        where = Locations.child(context.where, "#{keyword}[#{index}]")
        resolved = @resolver.call(branch, context.with(where:))
        return resolved if resolved.is_a?(Hash)

        raise SpecError.new("Ветка составной схемы должна быть объектом", where:)
      end

      def validate_branches!(keyword, branches, context, allow_empty:)
        valid = branches.is_a?(Array) && (allow_empty || !branches.empty?)
        return if valid

        qualifier = allow_empty ? "список" : "непустой список"
        where = Locations.child(context.where, keyword)
        raise SpecError.new("#{keyword} должен содержать #{qualifier} схем", where:)
      end

      def choice_note(keyword, where)
        NoteFactory.call(
          level: :needs_confirmation,
          where:,
          message: "#{keyword} содержит несколько вариантов; выбрана первая ветка"
        )
      end
    end

    module SchemaMerger
      module_function

      def call(left, right)
        return right unless left.is_a?(Hash) && right.is_a?(Hash)

        left.merge(right) { |key, old, new| merge_value(key, old, new) }
      end

      def merge_value(key, old, new)
        return call(old, new) if old.is_a?(Hash) && new.is_a?(Hash)
        return (old + new).uniq if key == "required" && old.is_a?(Array) && new.is_a?(Array)

        new
      end
    end

    class JsonPointer
      def initialize(root)
        @root = root
      end

      def follow(reference, at:)
        return @root if reference == "#"

        raise_invalid(reference, at) unless reference.start_with?("#/")

        parts(reference).reduce(@root) { |current, part| fetch(current, part, reference, at) }
      end

      private

      def parts(reference)
        reference.delete_prefix("#/").split("/").map do |part|
          part.gsub("~1", "/").gsub("~0", "~")
        end
      end

      def fetch(current, part, reference, at)
        return current.fetch(part) if current.is_a?(Hash) && current.key?(part)

        message = "Локальная ссылка ведёт в отсутствующий узел: #{reference}"
        raise ReferenceError.new(message, where: at)
      end

      def raise_invalid(reference, at)
        message = "Неверный формат локальной ссылки #{reference.inspect}"
        raise ReferenceError.new(message, where: at)
      end
    end

    class TreeCopier
      def initialize
        @copies = {}.compare_by_identity
      end

      def call(node)
        return @copies.fetch(node) if @copies.key?(node)

        case node
        when Hash then copy_hash(node)
        when Array then copy_array(node)
        when String then node.dup
        else node
        end
      end

      private

      def copy_hash(hash)
        copy = {}
        @copies[hash] = copy
        hash.each { |key, value| copy[call(key)] = call(value) }
        copy
      end

      def copy_array(array)
        copy = []
        @copies[array] = copy
        array.each { |value| copy << call(value) }
        copy
      end
    end

    module NoteFactory
      module_function

      def call(level:, where:, message:)
        note_class.new(level:, where:, message:)
      end

      def note_class
        defined?(Rsocket::Ir::Note) ? Rsocket::Ir::Note : LoaderNote
      end
    end

    module Locations
      module_function

      def child(parent, child)
        return child.delete_prefix(".") if parent.empty?
        return "#{parent}#{child}" if child.start_with?("[")

        "#{parent}.#{child}"
      end
    end
  end
end
