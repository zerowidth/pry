class Pry
  class CodeWriter
    INDENT_LEVEL = 2

    def initialize(*code_objects)
      @options = {}
      if code_objects.last.is_a?(Hash)
        @options = code_objects.pop
      end

      @code_objects = code_objects

      @options = {
        :order => :alphabetical,
        :visibility_sections => true,
        :convert_instance_methods_to_class => true,
        :include_comments => true
      }.merge!(@options)
    end

    def method_source(method_object)
      if @options[:covert_instance_methods_to_class]
        rewrite_instance_method_as_class_methods(method_object)
      else
        method_object.source
      end
    end

    def ordered_methods(*method_objects)
      if @options[:order] == :alphabetical
        method_objects.sort_by(&:name)
      elsif @options[:order] == :size
        method_objects.sort_by { |m| m.source.lines.count }
      else
        method_objects
      end
    end

    # TODO: put attr_* methods in specific place!!
    def build_source
      code_array = []

      class_methods, instance_methods = @code_objects.partition(&:singleton_method?)
      
      # instance_methods = all_methods[false] ? all_methods[false].group_by(&:visibility) : []
      # class_methods    = all_methods[true] ? all_methods[true].group_by(&:visibility) : []
      
      code_array << build_singleton_method_definitions(class_methods)
      code_array << build_method_definitions(instance_methods)

      binding.pry

      code_array.join
    end

    def build_singleton_method_definitions(methods)
      explicit, implicit = methods.partition { |m| explicit_class_method?(m) }

      code_array = []

      if !@options[:convert_instance_methods_to_class] && implicit.any?
        visibility_groups = implicit.group_by(&:visibility)
        code_array << "class << self\n\n"
        code_array << build_method_code(visibility_groups, INDENT_LEVEL)
        code_array << "end\n"
      else
        visibility_groups = (explicit + implicit).group_by(&:visibility?)
        code_array << build_method_code(visibility_groups, INDENT_LEVEL)
      end

      code_array.join
    end

    def build_method_code(visibility_groups, indent_level)
      code_array = []
      visibility_groups.each do |visibility, methods|
        code_array << Pry::Helpers::Text.indent(visibility.to_s << "\n\n", indent_level)
        ordered_methods(*methods).each do |v|
          code_array << Pry::Helpers::Text.indent(v.doc(true), indent_level) if @options[:include_comments]
          code_array << Pry::Helpers::Text.indent(method_source(v), indent_level)
          code_array << "\n"
        end
      end
      code_array.join
    end
    
    def build_method_definitions(methods)
      visibility_groups = methods.group_by(&:visibility)
      build_method_code(visibility_groups, 0)
    end

    # @param [Pry::Method] method_object 
    # @return [Boolean] Whether the method is of the form `def self.*` or `define_singleton_method`
    def explicit_class_method?(method_object)
      method_object.source.lines.first =~ /^def self\.|^define_singleton_method/
    end
        
    # @param [Pry::Method] method_object The instance method to
    #   rewrite as a class method.
    # @return [String] The rewritten method source.
    def rewrite_instance_method_as_class_methods(method_object)
      if explicit_class_method?(method_object)
        return method_object.source
      end
      
      line = method_object.source.lines.first
      if line =~ /^def #{Regexp.escape(method_object.name)}(?=[\(\s;]|$)/
        src = method_object.source.lines.to_a
        src[0] = "def self.#{method_object.name}#{$'}"
        src.join
      elsif line =~ /^define_method/
        method_object.source.sub /^define_method/, "define_singleton_method"
      else
        method_object.source
      end
    end
  end
end
