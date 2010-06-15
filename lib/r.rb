module R
  # not so thread-safe, having only one instance -- but the web-interface
  # is just a single user interface anyway for the application
  RInstance = RSRuby.instance
  
  def self.eval(&block)
    return RInstance.instance_eval &block
  end

	def self.method_missing(method_sym, *arguments, &block)
		method_string = method_sym.to_s
		begin
			return RInstance.send(method_sym, *arguments)
    rescue
			super
		end
	end

  # this will be slooooowwwww
  def self.respond_to?(method_sym)
		begin
			RInstance.send method_sym
      return true
    rescue
      super
		end
	end
end