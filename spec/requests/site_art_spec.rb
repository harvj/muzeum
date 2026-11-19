require "rails_helper"

RSpec.describe "Site Art snapshot", type: :request do
  it "serves the public cached projection without an auth redirect or a storable response" do
    snapshot = { release: "a" * 64, light: { url: "https://art.harvj.com/assets/#{"b" * 64}.png" } }
    allow(SiteArt).to receive(:snapshot).and_return(snapshot)

    get "/site-art"
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.parsed_body).to eq(snapshot.deep_stringify_keys)
  end
end
