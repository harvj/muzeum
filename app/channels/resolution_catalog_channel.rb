class ResolutionCatalogChannel < Turbo::StreamsChannel
  def subscribed
    stream = verified_stream_name_from_params
    match = /\Aresolution_catalog:(\d+)\z/.match(stream.to_s)
    return reject unless match

    @recording_id = match[1]
    stream_from stream
  end

  private

  # Action Cable confirms only after the pub/sub subscription is active. Catch
  # imports that finished while the redirected page was opening its socket.
  def transmit_subscription_confirmation
    super
    recording = Recording.find_by(id: @recording_id)
    return unless recording && !CatalogImport.latest("recording", recording.id)&.active?

    context = RecordingResolution::CatalogContext
    html = ApplicationController.render(partial: "resolution_workspace/catalog_context", locals: { rows: context.rows(recording) })
    transmit(Turbo::StreamsChannel.turbo_stream_action_tag(:update, target: context.target(recording), template: html))
  end
end
