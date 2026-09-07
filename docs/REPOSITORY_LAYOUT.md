# Repository layout

The `mrworf/opi5-aosptv` controller owns bootstrap, build, validation, and
release policy. Android checkouts live under `sources/`, optional machine-local
configuration under `local/`, and completed images under `releases/`. Local
publication mirrors may live under `remotes/`. These generated and local paths
are ignored by Git.

Modified Android components use the `opi5-aosptv-` repository prefix followed
by their Android repo name, for example
`opi5-aosptv-android_packages_apps_TvSettings`. Components publish the
`android-17.0-opi5-tv` integration branch, while the build manifest pins
immutable commit IDs rather than moving branches.

The OSS profile uses only the projects pinned in `manifests/opi5-public.xml.in`.
Optional user-created manifest overlays are read from `local/customization`
only when the custom profile is selected. Their hosting and contents are
entirely outside the controller's configuration.
