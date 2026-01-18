require "cgi"

module SimpleLogger
  def log(message)
    logger.info("[#{log_prefix}] #{message}")
  end

  def redact(query, *sensitive_keys)
    params = CGI.parse(query)

    sensitive_keys.map(&:to_s).each do |key|
      if params.key?(key)
        params[key] = %w([REDACTED])
      end
    end

    params.map { |k, v| "#{k}=#{v.first}" }.join("&")
  end

  private

  def logger
    @logger ||= begin
      if cli_execution?
        cli_logger
      elsif defined?(Rails) && Rails.logger
        Rails.logger
      else
        null_logger
      end
    end
  end

  def cli_execution?
    $PROGRAM_NAME.include?("bin/")
  end

  def cli_logger
    require "logger"
    Logger.new($stdout).tap do |l|
      l.level = Logger::INFO
      l.formatter = proc do |_severity, _time, _progname, msg|
        "#{msg}\n"
      end
    end
  end

  def null_logger
    require "logger"
    Logger.new(nil)
  end

  def log_prefix
    self.class.name
  end
end
