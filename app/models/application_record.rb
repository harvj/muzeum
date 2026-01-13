class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  VALID_SOURCES = %w[
    lastfm
    musicbrainz
    discogs
    spotify
    manual
  ].freeze
end
