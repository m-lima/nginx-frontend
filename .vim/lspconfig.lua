return {
  Lua = {
    diagnostics = {
      globals = { 'ngx' },
    },
    workspace = {
      checkThirdParty = false,
      library = '${3rd}/OpenResty/library',
    },
  }
}
