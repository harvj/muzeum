module LadyWoodFixture
  GROUP = "3b5fece9-e8ec-4713-9fc0-56f3b03e50c1"
  SINGLE = "0e399e2a-c332-444d-abfc-8191a63a72fd"
  OFFICIAL = "e3f12607-2004-448a-9a6a-421a8a59ee9b"

  class Session
    attr_reader :provenance, :fixture
    attr_accessor :unavailable_recording_browse, :unavailable_single

    def initialize
      @provenance = []
      @fixture = JSON.parse(Rails.root.join("spec/fixtures/musicbrainz/construction/lady_wood.json").read)
    end

    def get(_, path, params:)
      @provenance << { "endpoint" => path, "parameters" => params }
      id = path.split("/").last
      data = if params[:recording]
        if params[:recording] == unavailable_recording_browse
          raise RecordingResolution::ProviderError.new("Recording browse unavailable", http_status: 503)
        end
        fixture.fetch("recording_browse").fetch(params[:recording]).find { |page| page.fetch("release-offset") == params.fetch(:offset, 0) }
      elsif params["release-group"]
        case params["release-group"]
        when GROUP then fixture.fetch("group_browse")
        when SINGLE
          raise RecordingResolution::ProviderError.new("A separate single could not be checked", http_status: 503) if unavailable_single

          fixture.fetch("single_browse")
        else
          raise "Unexpected release group #{params['release-group']}"
        end
      elsif path.start_with?("/ws/2/recording/")
        fixture.fetch("recordings").fetch(id)
      else
        fixture.fetch("editions").fetch(id)
      end
      { "data" => yield(data) }
    end
  end
end
