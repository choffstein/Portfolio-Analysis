# this kernel patch allows us to utilize any r method one-off by r_*, or, for
# blocks, use r_eval { ... }.
module RKernel
  def r_eval(&block)
    return RSRuby.instance.instance_eval &block
  end

	alias :old_method_missing :method_missing
	def method_missing(method_sym, *arguments, &block)
		method_string = method_sym.to_s
		if method_string =~ /^r_(.*)$/
			return RSRuby.instance.send(method_string.split('r_')[1].to_sym, *arguments)
		else
			old_method_missing(method_sym, *arguments, &block)
		end
	end

	alias :old_respond_to? :respond_to?
	def respond_to?(method_sym)
		if method_sym.to_s =~ /^r_(.*)$/
			true
		else
			old_respond_to?(method_sym)
		end
	end
end

module Kernel
  include RKernel
end