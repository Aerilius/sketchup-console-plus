module AE

  module ConsolePlugin

    require(File.join(PATH, 'observable.rb'))

    class Settings

      include Observable

      def initialize(section)
        @section = section
        @properties = {}
      end

      # Retrieves a value of a property by its name.
      # If the property does not exist, the property is created with the given value.
      # @param name  [String] The name of the property
      # @param value [Object] The new value to set
      # @return [Object]  The value
      def set(name, value)
        name = name.to_sym
        if @properties.include?(name)
          @properties[name].set_value(value)
        else
          add_property(name, value)
        end
        return value
      end
      alias_method :[]=, :set

      # Retrieves a value of a property by its name.
      # If the property does not exist, an empty property is created.
      # @param name          [String] The name of the property
      # @param default_value [Object] An optional default value to return if the property does not exist.
      # @return [Object]  The value
      def get(name, default_value=nil)
        name = name.to_sym
        if @properties.include?(name)
          return @properties[name].get_value()
        elsif default_value
          return default_value
        end
      end
      alias_method :[], :get

      # Retrieves a property by its name.
      # If the property does not exist, an empty property is created.
      # @param name [String]  The name of the property to retrieve
      # @param default_value [Object] An optional default value to return if the property does not exist.
      # @return [Property, nil] Returns the property or nil if the property does not exist
      #   and no default value was provided. The default is needed for type validation.
      def get_property(name, default_value=nil)
        name = name.to_sym
        if @properties.include?(name)
          return @properties[name]
        elsif default_value
          return add_property(name, default_value)
        end
      end

      # Check whether a property exists.
      # @param name [String]  The name of the property
      # @return [Boolean]  True if the property exists, false otherwise.
      def has(name)
        return @properties.include?(name.to_sym)
      end

      # Sets many properties at once.
      # @param settings [Hash] An object literal containing strings as keys.
      def load(settings)
        settings.each{ |name, value|
          name = name.to_sym
          if @properties.include?(name)
            property = @properties[name]
            property.set_value(value) if value != property.get_value()
          else
            add_property(name, value)
          end
        }
        return self
      end

      # Returns a hash of all properties ke and values.
      # @return [Hash]
      def to_hash()
        hash = {}
        @properties.each{ |key, property|
          hash[key.to_s] = property.get_value()
        }
        return hash
      end

      private

      def add_property(name, value)
        name = name.to_sym
        property = Property.new(name, value, @section)
        property.add_listener(:change) { |new_value|
          trigger(:change, name, new_value)
        }
        @properties[name] = property
        return property
      end

    end # class Settings

    class Property

      include Observable

      def initialize(name, initial_value, section)
        super()
        @section = section
        @name = name.to_sym
        read_value = Sketchup.read_default(@section.to_s, @name.to_s, initial_value)
        # Type validation. If values read from the registry have an incorrect type, it might cause unexpected behavior in the program.
        # Since booleans are distinct classes, we need to check if initial_value is a boolean that also read_value is any boolean.
        @initial_value = (read_value.is_a?(initial_value.class) || ([initial_value, read_value]-[true, false]).empty?) ? read_value : initial_value
      end

      def get_name()
        return @name
      end

      def set_value(new_value)
        new_value = case new_value
        when String
          # Sketchup does not properly escape strings but just adds quotes.
          new_value.gsub(/\\/, '\\\\\\').gsub(/\"/, '\\\"')
        when Symbol
          new_value.to_s
        when Length
          new_value.to_f
        else
          new_value
        end
        # Sketchup still removes nil from arrays.
        # A work-around that writes all data types properly is 
        # to always pack the value in a hash (and always unpack it when reading).
        Sketchup.write_default(@section.to_s, @name.to_s, new_value)
        trigger(:change, new_value)
        nil
      end

      def get_value()
        return Sketchup.read_default(@section.to_s, @name.to_s, @initial_value)
      end

    end # class Property

  end # module ConsolePlugin

end # module AE
