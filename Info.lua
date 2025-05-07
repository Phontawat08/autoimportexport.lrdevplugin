return {

	LrSdkVersion = 3.0,
	LrSdkMinimumVersion = 1.3, -- minimum SDK version required by this plug-in

	LrToolkitIdentifier = 'org.365labs.app.pixid.autopresetsavetodisk',

	LrPluginName = LOC "$$$/AutoImportExport/PluginName= Plug-in Auto Export Images -V Two ", -- Pixid Save-to-Disk Plug-in

	LrExportMenuItems = { {
		title = "Auto Export Images ", -- Save-to-disk Console ...
		file = "ExportMenuItem.lua",
	} },
	VERSION = { major = 1, minor = 0, revision = 0, build = "20220724", },

}
