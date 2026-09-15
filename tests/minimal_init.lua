local root = vim.fn.getcwd()

vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. "/deps/mini.nvim")

require("mini.test").setup()
