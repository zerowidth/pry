class Pry
  def self.SafeProxy(obj)
    SafeProxy.new(obj)
  end

  # SafeProxy is a class that wraps an object and translates any method call
  # into a call to the equivalent instance method defined on Kernel or Class.
  # This is useful for calling introspection methods on objects that may have
  # overridden them with incompatible behavior (or, under Ruby 2.0, objects
  # that inherit from BasicObject and therefore don't have Kernel in their
  # ancestry chain).
  class SafeProxy < BasicObject
    def initialize(obj)
      @obj = obj
      @mod = ::Module === obj ? ::Module : ::Kernel
    end

    def respond_to?(method_name, include_private = false)
      __safe_send__(:methods).include?(method_name) # TODO: improve this
    end

    def method_missing(method_name, *args, &block)
      __safe_send__(method_name, *args, &block)
    end

    private

    def __safe_send__(method_name, *args, &block)
      @mod.instance_method(method_name).bind(@obj).call(*args, &block)
    end
  end
end
