require 'rsruby'

class R
  def self.eval(&block)
    return RSRuby.instance.instance_eval &block
  end

	def self.method_missing(method_sym, *arguments, &block)
		method_string = method_sym.to_s
		begin
			return RSRuby.instance.send(method_string.split('r_')[1].to_sym, *arguments)
    rescue
			super
		end
	end

  # should implement a respond_to? here
end