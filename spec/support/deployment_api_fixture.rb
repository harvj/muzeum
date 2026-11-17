class DeploymentApiFixture
  attr_accessor :fail_next, :hide_records
  attr_reader :creates, :statuses

  def initialize
    @creates, @statuses, @records = [], [], []
  end

  def states
    @statuses.map { |status| status[:state] }
  end

  def duplicate!
    @records << @records.first.merge("id" => 2)
  end

  def call(method, path, body = nil)
    if fail_next == :before
      self.fail_next = nil
      raise MuzeumDeploymentReporting::Error, "Synthetic API unavailable"
    end
    if method == "GET"
      return hide_records ? [] : @records if path.include?("deployments?")
      return @statuses.reverse.map { |status| { "state" => status[:state] } }.first(1) if path.include?("statuses?")
      @records.find { |record| record["id"] == path.split("/").last.to_i }
    elsif path.end_with?("/deployments")
      @creates << body
      @records << { "id" => 1, "sha" => body[:ref], "environment" => "production", "payload" => JSON.parse(JSON.generate(body[:payload])) }
      if fail_next == :after_create
        self.fail_next = nil
        raise MuzeumDeploymentReporting::Error, "Synthetic lost create response"
      end
      @records.last
    else
      @statuses << body
      if fail_next == :after_status
        self.fail_next = nil
        raise MuzeumDeploymentReporting::Error, "Synthetic lost status response"
      end
      { "id" => @statuses.size }
    end
  end
end
