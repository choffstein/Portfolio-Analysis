module Status
  
  def self.start
    @@status = [:started]
  end
  def self.error(msg)
    Rails.logger.error(msg)
    @@status = [:error, msg]
  end

  def self.info(msg)
    Rails.logger.info(msg)
    @@status = [:info, msg]
  end

  def self.update(msg)
    Rails.logger.info(msg)
    @@status = [:update, msg]
  end

  def self.finished(msg = nil)
    Rails.logger.info(msg) unless msg.nil?
    @@status = [:finished, msg]
  end

  def self.render
    @@status ||= []
    return @@status
  end
end