# Muzeum v0.7.1 — Featured-Artist Discovery and Ordered Artist Credits

Muzeum can find recordings when Last.fm includes a featured performer in the title and MusicBrainz lists that performer in a separate artist credit. For example, the investigation searches both “Cross You Out (feat. Sky Ferreira)” and “Cross You Out” with the two artist credits. It can then verify the recording as track 3 of the 15-track Charli album. Evidence shows the search queries and their outcomes. The reported Last.fm strings remain intact.

Recording and release pages, catalog results, and Resolution show credited artists as comma-separated names in source order, such as “Charli xcx, Sky Ferreira.” Each recording and release has its own credit list. Original credited names and join phrases remain in source evidence, and every credited artist remains linked to the catalog.

This is a maintenance release with no database migration.
