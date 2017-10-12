module HelperMethods

  private

  def get_class_of_snake_model_name(snake_model_name)
    Object.const_get( snake_model_name.split('_').map(&:capitalize).join )
  end

  def sfo_single_attr_regexp
    /^([^-]+)-([^-]+)$/
  end

  def sfo_date_attr_regexp
    /^([^-]+)-([^-]+)(\([\s\S]+\))$/
  end

  def sfo_collection_ads_regexp
    /_ids$/
  end

  def sfo_form_attribute?(object)
    object.class.ancestors[1] == SlimFormObject::Base if object
  end

  def sfo_attr?(method)
    sfo_single_attr?(method)
  end

  def sfo_single_attr?(method)
    method.to_s[sfo_single_attr_regexp] ? true : false
  end

  def sfo_date_attr?(tag_name)
    tag_name.to_s[sfo_date_attr_regexp] ? true : false
  end

  def sfo_collection_ads_attr?(tag_name)
    tag_name.to_s[sfo_collection_ads_regexp] ? true : false
  end

  def sfo_get_tag_name(object_name, method, multiple, options)
    model_name, attr_name = apply_expression_text(method, sfo_single_attr_regexp)

    if options[:sfo_nested]
      if options[:sfo_main]
        tag_name = "#{object_name}[#{model_name}][][#{attr_name}]#{"[]" if multiple}"
      else
        tag_name = "#{object_name}[][#{model_name}][][#{attr_name}]#{"[]" if multiple}"
      end
    elsif sfo_single_attr?(method)
      tag_name   = "#{object_name}[#{model_name}][#{attr_name}]#{"[]" if multiple}"
    end

    tag_name
  end

  def sfo_get_method_name(method)
    if sfo_single_attr?(method) and !sfo_collection_ads_attr?(method)
      model_name, attr_name = apply_expression_text(method, sfo_single_attr_regexp)
      method = "#{model_name}_#{attr_name}"
    end

    method
  end

  def sfo_get_date_tag_name(prefix, tag_name, options)
    model_name, attr_name, date_type = apply_expression_date(tag_name, sfo_date_attr_regexp)

    if options[:sfo_nested]
      tag_name   = "#{prefix}[#{model_name}][][#{attr_name}#{date_type}]"
    else
      tag_name   = "#{prefix}[#{model_name}][#{attr_name}#{date_type}]"
    end

    tag_name
  end

  def apply_expression_date(string, exp)
    string[exp]
    model_name = $1
    attr_name  = $2
    date_type  = $3

    [model_name, attr_name, date_type]
  end

  def apply_expression_text(string, exp)
    string[exp]
    model_name = $1
    attr_name  = $2

    [model_name, attr_name]
  end
end

module ActionView
  module Helpers
    # EXTENSIONS

    class DateTimeSelector
      include HelperMethods

      def input_name_from_type(type)
        prefix = @options[:prefix] || ActionView::Helpers::DateTimeSelector::DEFAULT_PREFIX
        prefix += "[#{@options[:index]}]" if @options.has_key?(:index)

        field_name = @options[:field_name] || type
        if @options[:include_position]
          field_name += "(#{ActionView::Helpers::DateTimeSelector::POSITION[type]}i)"
        end
        options = self.instance_variable_get(:@options)
        return sfo_get_date_tag_name(prefix, field_name, options) if sfo_date_attr?(field_name)

        @options[:discard_type] ? prefix : "#{prefix}[#{field_name}]"

      end
    end

    module Tags
      class Base
        include HelperMethods

        private

        def value(object)
          method_name = sfo_get_method_name(@method_name)
          object.public_send method_name if object
        end

        def tag_name(multiple = false, index = nil)
          options = self.instance_variable_get(:@options)
          return sfo_get_tag_name(@object_name, sanitized_method_name, multiple, options) if sfo_attr?(sanitized_method_name)

          if index
            "#{@object_name}[#{index}][#{sanitized_method_name}]#{"[]" if multiple}"
          else
            "#{@object_name}[#{sanitized_method_name}]#{"[]" if multiple}"
          end
        end
      end
    end

    class FormBuilder
      include HelperMethods

      def initialize(object_name, object, template, options)
        @nested_child_index = {}
        @object_name, @object, @template, @options = object_name, object, template, options
        @default_options = @options ? @options.slice(:index, :namespace, :skip_default_ids, :allow_method_names_outside_object) : {}
        @default_options.merge!( {sfo_nested: options[:sfo_nested], sfo_main: options[:sfo_main]} )
        convert_to_legacy_options(@options)

        if @object_name.to_s.match(/\[\]$/)
          if (object ||= @template.instance_variable_get("@#{Regexp.last_match.pre_match}")) && object.respond_to?(:to_param)
            @auto_index = object.to_param
          else
            raise ArgumentError, "object[] naming but object param and @object var don't exist or don't respond to to_param: #{object.inspect}"
          end
        end

        @multipart = nil
        @index = options[:index] || options[:child_index]
      end

      def fields_for(record_name, record_object = nil, fields_options = {}, &block)
        (self.options[:sfo_nested] and record_object) ? record_object.merge!({sfo_main: false}) : record_object.merge!({sfo_main: true})
        fields_options, record_object = record_object, nil if record_object.is_a?(Hash) && record_object.extractable_options?
        fields_options[:builder] ||= options[:builder]
        fields_options[:namespace] = options[:namespace]
        fields_options[:parent_builder] = self

        case record_name
        when String, Symbol
          if nested_attributes_association?(record_name)
            return fields_for_with_nested_attributes(record_name, record_object, fields_options, block)
          end
        else
          record_object = record_name.is_a?(Array) ? record_name.last : record_name
          record_name   = model_name_from_record_or_class(record_object).param_key
        end

        object_name = @object_name
        index = if options.has_key?(:index)
          options[:index]
        elsif defined?(@auto_index)
          object_name = object_name.to_s.sub(/\[\]$/, "")
          @auto_index
        end

        record_name = if index
          "#{object_name}[#{index}][#{record_name}]"
        elsif record_name.to_s.end_with?("[]")
          record_name = record_name.to_s.sub(/(.*)\[\]$/, "[\\1][#{record_object.id}]")
          "#{object_name}#{record_name}"
        else
          "#{object_name}[#{record_name}]"
        end
        fields_options[:child_index] = index

        if fields_options[:sfo_nested]
          record_object = object
          record_name = record_name + '[]'
        end
        @template.fields_for(record_name, record_object, fields_options, &block)
      end
    end

    module FormHelper
      include HelperMethods

      # def fields_for(record_name, record_object = nil, options = {}, &block)
      #   builder = instantiate_builder(record_name, record_object, options)
      #   capture(builder, &block)
      # end
    end

  end
end
