return function(server)
  return {
    Lua = {
      diagnostics = {
        globals = { 'ngx' },
      },
      workspace = {
        checkThirdParty = false,
        library = {
          server.root_dir .. '/extension/server/meta/3rd/OpenResty/library',
        },
      },
    }
  }
end
