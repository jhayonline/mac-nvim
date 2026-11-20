return {
    "mfussenegger/nvim-dap",
    dependencies = { "nvim-neotest/nvim-nio" },

    config = function()
        local dap = require("dap")
        local uv = vim.uv or vim.loop

        local function file_exists(path)
            return path and uv.fs_stat(path) ~= nil
        end

        local function is_executable(path)
            return file_exists(path) and vim.fn.executable(path) == 1
        end

        local function workspace_root()
            local current = vim.api.nvim_buf_get_name(0)
            local root_markers = {
                ".git",
                "compile_commands.json",
                "CMakeLists.txt",
                "Cargo.toml",
                "Makefile",
            }

            local root = vim.fs.dirname(vim.fs.find(root_markers, {
                path = current ~= "" and current or vim.fn.getcwd(),
                upward = true,
            })[1] or "")

            return root ~= "" and root or vim.fn.getcwd()
        end

        local function pick_cpp_binary()
            local cwd = workspace_root()
            local current = vim.api.nvim_buf_get_name(0)
            local stem = vim.fn.fnamemodify(current, ":t:r")
            local candidates = {
                cwd .. "/" .. stem,
                cwd .. "/build/" .. stem,
                cwd .. "/bin/" .. stem,
                cwd .. "/build/debug/" .. stem,
                cwd .. "/build/Debug/" .. stem,
                cwd .. "/out/" .. stem,
            }

            for _, candidate in ipairs(candidates) do
                if is_executable(candidate) then
                    vim.notify("DAP launching " .. candidate, vim.log.levels.INFO)
                    return candidate
                end
            end

            local picked = vim.fn.input("Path to executable: ", cwd .. "/", "file")
            if picked == "" then
                vim.notify("DAP launch cancelled: no executable selected", vim.log.levels.WARN)
                return nil
            end
            if not is_executable(picked) then
                vim.notify("DAP launch aborted: not executable: " .. picked, vim.log.levels.ERROR)
                return nil
            end
            return picked
        end

        local function split_args(input)
            local args = {}
            for arg in string.gmatch(input, "%S+") do
                table.insert(args, arg)
            end
            return args
        end

        local function prompt_args()
            return split_args(vim.fn.input("Program arguments: "))
        end

        -- Mason installs into its own bin directory, which is deliberately
        -- not on $PATH, so exepath() alone never found codelldb -- which is
        -- why this file has been warning "No C/C++ DAP adapter found" on
        -- every startup even after installing one. Check Mason too.
        local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"

        local function find_adapter(name)
            local on_path = vim.fn.exepath(name)
            if on_path ~= "" then
                return on_path
            end

            local in_mason = mason_bin .. "/" .. name
            if is_executable(in_mason) then
                return in_mason
            end

            -- On macOS, Xcode / Command Line Tools ship lldb-dap but only
            -- expose it through xcrun, not on $PATH.
            if vim.fn.has("mac") == 1 and vim.fn.executable("xcrun") == 1 then
                local found = vim.fn.trim(vim.fn.system({ "xcrun", "-f", name }))
                if vim.v.shell_error == 0 and is_executable(found) then
                    return found
                end
            end

            return ""
        end

        local lldb_dap = find_adapter("lldb-dap")
        local codelldb = find_adapter("codelldb")

        -----------------------------------------------------------------------
        -- Adapter setup
        -----------------------------------------------------------------------
        if lldb_dap ~= "" then
            dap.adapters.lldb = {
                type = "executable",
                command = lldb_dap,
                name = "lldb",
            }
        elseif codelldb ~= "" then
            dap.adapters.lldb = {
                type = "server",
                port = "${port}",
                executable = {
                    command = codelldb,
                    args = { "--port", "${port}" },
                },
            }
        else
            vim.notify(
                "No C/C++ DAP adapter found. Install `lldb-dap` or `codelldb`.",
                vim.log.levels.WARN
            )
        end

        -----------------------------------------------------------------------
        -- Debug configurations for C, C++, Rust
        -----------------------------------------------------------------------
        local cpp_configurations = {
            {
                name = "Launch",
                type = "lldb",
                request = "launch",
                program = pick_cpp_binary,
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
            },
            {
                name = "Launch with args",
                type = "lldb",
                request = "launch",
                program = pick_cpp_binary,
                args = prompt_args,
                cwd = "${workspaceFolder}",
                stopOnEntry = false,
            },
            {
                name = "Attach to process",
                type = "lldb",
                request = "attach",
                pid = require("dap.utils").pick_process,
                cwd = "${workspaceFolder}",
            },
        }

        dap.configurations.cpp = cpp_configurations
        dap.configurations.c = cpp_configurations
		-- Rust uses the same plain CodeLLDB configurations as C/C++ now that
		-- rustaceanvim is disabled. Build the target with Cargo first.
        dap.configurations.rust = cpp_configurations

        -----------------------------------------------------------------------
        -- .NET / C# via netcoredbg
        -----------------------------------------------------------------------
        -- netcoredbg speaks DAP directly (`--interpreter=vscode`), so no
        -- adapter shim is needed. Installed with :MasonInstall netcoredbg.
        local netcoredbg = vim.fn.exepath("netcoredbg")
        if netcoredbg == "" then
            local mason_netcoredbg = vim.fn.stdpath("data") .. "/mason/bin/netcoredbg"
            if is_executable(mason_netcoredbg) then
                netcoredbg = mason_netcoredbg
            end
        end

        if netcoredbg ~= "" then
            dap.adapters.coreclr = {
                type = "executable",
                command = netcoredbg,
                args = { "--interpreter=vscode" },
            }

            -- Find the built assembly for the project the buffer belongs to.
            -- `dotnet build` writes bin/<config>/<tfm>/<AssemblyName>.dll, and
            -- the TFM changes with every SDK bump, so glob rather than guess.
            local function pick_dotnet_dll()
                local dotnet = require("engine.core.dotnet")
                local csproj = dotnet.project()

                if not csproj then
                    return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/", "file")
                end

                local project_dir = vim.fs.dirname(csproj)
                local assembly = dotnet.msbuild_property(csproj, "AssemblyName")
                    or vim.fn.fnamemodify(csproj, ":t:r")

                -- Debug before Release: you are debugging, after all.
                for _, config in ipairs({ "Debug", "Release" }) do
                    local hits = vim.fn.glob(
                        project_dir .. "/bin/" .. config .. "/*/" .. assembly .. ".dll",
                        false,
                        true
                    )
                    if #hits > 0 then
                        -- Newest wins when several target frameworks are built.
                        table.sort(hits, function(a, b)
                            local sa = vim.uv.fs_stat(a)
                            local sb = vim.uv.fs_stat(b)
                            return (sa and sa.mtime.sec or 0) > (sb and sb.mtime.sec or 0)
                        end)
                        vim.notify("DAP launching " .. hits[1], vim.log.levels.INFO)
                        return hits[1]
                    end
                end

                vim.notify(
                    "No built assembly under " .. project_dir .. "/bin -- run :DotnetBuild first",
                    vim.log.levels.WARN
                )
                return vim.fn.input("Path to dll: ", project_dir .. "/bin/", "file")
            end

            dap.configurations.cs = {
                {
                    name = "Launch",
                    type = "coreclr",
                    request = "launch",
                    program = pick_dotnet_dll,
                    cwd = "${workspaceFolder}",
                    stopAtEntry = false,
                },
                {
                    -- ASP.NET needs Development to pick up appsettings.
                    -- Development.json, user secrets and the dev exception page.
                    name = "Launch (ASP.NET Development)",
                    type = "coreclr",
                    request = "launch",
                    program = pick_dotnet_dll,
                    cwd = "${workspaceFolder}",
                    stopAtEntry = false,
                    env = {
                        ASPNETCORE_ENVIRONMENT = "Development",
                        DOTNET_ENVIRONMENT = "Development",
                    },
                },
                {
                    -- For attaching to an already-running `dotnet watch`.
                    name = "Attach to process",
                    type = "coreclr",
                    request = "attach",
                    processId = require("dap.utils").pick_process,
                },
            }

            dap.configurations.razor = dap.configurations.cs
            dap.configurations.fsharp = dap.configurations.cs
        else
            -- Don't nag on every startup; only complain when a C# debug
            -- session is actually requested. Note: Mason's netcoredbg is an
            -- x86_64 build, which can't debug arm64 .NET on Apple Silicon --
            -- use an arm64 build of netcoredbg on $PATH instead.
            dap.adapters.coreclr = function()
                vim.notify(
                    "netcoredbg not found -- put an arm64 netcoredbg on $PATH for C# debugging.",
                    vim.log.levels.WARN
                )
            end
            dap.configurations.cs = {
                { name = "Launch (netcoredbg missing)", type = "coreclr", request = "launch" },
            }
        end

        -----------------------------------------------------------------------
        -- Keybindings
        -----------------------------------------------------------------------
        vim.keymap.set("n", "<leader>dc", dap.continue,          { desc = "Continue" })
        vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, { desc = "Breakpoint" })
        vim.keymap.set("n", "<leader>ds", dap.step_over,         { desc = "Step Over" })
        vim.keymap.set("n", "<leader>di", dap.step_into,         { desc = "Step Into" })
        vim.keymap.set("n", "<leader>do", dap.step_out,          { desc = "Step Out" })
        vim.keymap.set("n", "<leader>dr", dap.restart,           { desc = "Restart" })
        vim.keymap.set("n", "<leader>dt", dap.terminate,         { desc = "Terminate" })
    end,
}
