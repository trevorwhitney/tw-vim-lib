-- Standalone tests for resolve_file_path()
-- Run: lua test/resolve_file_path_test.lua (or via make test-lua)
--
-- Stubs vim and plenary.path so this runs outside Neovim.

-- Stub plenary.path before anything requires it
package.preload["plenary.path"] = function()
    local Path = {}
    Path.__index = Path
    setmetatable(Path, {
        __call = function(cls, _, path_str)
            return setmetatable({ filename = path_str }, cls)
        end,
    })
    function Path:make_relative(root)
        if root and self.filename:sub(1, #root) == root then
            local rel = self.filename:sub(#root + 2) -- skip the trailing /
            return rel
        end
        return self.filename
    end
    function Path:new(path_str)
        return setmetatable({ filename = path_str }, Path)
    end
    return Path
end

-- Minimal vim stub
vim = vim
    or {
        fn = {
            expand = function()
                return ""
            end,
            filereadable = function()
                return 0
            end,
        },
        api = {
            nvim_list_bufs = function()
                return {}
            end,
        },
        bo = setmetatable({}, {
            __index = function()
                return {}
            end,
        }),
    }

-- Adjust package.path to find our module
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local util = require("tw.agent.util")

local pass_count = 0
local fail_count = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        pass_count = pass_count + 1
        print("  PASS: " .. name)
    else
        fail_count = fail_count + 1
        print("  FAIL: " .. name)
        print("        " .. tostring(err))
    end
end

local function eq(expected, actual, msg)
    if expected ~= actual then
        error(
            (msg or "")
                .. " expected: "
                .. tostring(expected)
                .. ", got: "
                .. tostring(actual)
        )
    end
end

print("resolve_file_path tests:")
print()

test("regular absolute path returns unchanged", function()
    local path, root = util.resolve_file_path("/Users/foo/project/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq(nil, root, "root")
end)

test("commit diffview URI extracts real path", function()
    local path, root =
        util.resolve_file_path("diffview:///Users/foo/project/.git/abc1234def0/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("stage diffview URI extracts real path", function()
    local path, root =
        util.resolve_file_path("diffview:///Users/foo/project/.git/:0:/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("stage 2 diffview URI extracts real path", function()
    local path, root =
        util.resolve_file_path("diffview:///Users/foo/project/.git/:2:/src/bar.lua")
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("null diffview buffer returns nil", function()
    local path, root = util.resolve_file_path("diffview://null")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

test("empty string returns nil", function()
    local path, root = util.resolve_file_path("")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

test("malformed diffview URI returns nil", function()
    local path, root = util.resolve_file_path("diffview://something-unexpected")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

test(".git in parent dir uses last .git anchor", function()
    local path, root = util.resolve_file_path(
        "diffview:///Users/foo/.git-projects/repo/.git/abc123/src/bar.lua"
    )
    eq("/Users/foo/.git-projects/repo/src/bar.lua", path, "path")
    eq("/Users/foo/.git-projects/repo", root, "root")
end)

test("deeply nested file path in commit URI", function()
    local path, root = util.resolve_file_path(
        "diffview:///home/user/work/.git/d4a7b0d/lua/tw/agent/init.lua"
    )
    eq("/home/user/work/lua/tw/agent/init.lua", path, "path")
    eq("/home/user/work", root, "root")
end)

test("full SHA in commit URI", function()
    local path, root = util.resolve_file_path(
        "diffview:///Users/foo/project/.git/abc1234def0abc1234def0abc1234def0abc1234d/src/bar.lua"
    )
    eq("/Users/foo/project/src/bar.lua", path, "path")
    eq("/Users/foo/project", root, "root")
end)

test("diffview URI with no rev component returns nil", function()
    local path, root = util.resolve_file_path("diffview:///Users/foo/project/.git/")
    eq(nil, path, "path")
    eq(nil, root, "root")
end)

-- Worktree tests require temporary gitdir files to resolve the worktree root.
-- Helper to create the necessary directory structure.
local function setup_worktree_gitdir(main_repo, wt_name, wt_root)
    local dir = main_repo .. "/.git/worktrees/" .. wt_name
    os.execute('mkdir -p "' .. dir .. '"')
    local fh = io.open(dir .. "/gitdir", "w")
    fh:write(wt_root .. "/.git\n")
    fh:close()
    return dir
end

local function cleanup_worktree_gitdir(main_repo)
    os.execute('rm -rf "' .. main_repo .. '"')
end

-- Use /tmp for test fixtures
local tmp_main = os.tmpname() .. "_main_repo"
os.remove(tmp_main) -- tmpname creates the file on some systems
os.execute('mkdir -p "' .. tmp_main .. '/.git"')

test("worktree stage diffview URI resolves to worktree root", function()
    setup_worktree_gitdir(tmp_main, "gold-pond", "/Users/foo/workspace/gold-pond")
    local path, root = util.resolve_file_path(
        "diffview://" .. tmp_main .. "/.git/worktrees/gold-pond/:0:/pkg/dataobj/builder.go"
    )
    eq("/Users/foo/workspace/gold-pond/pkg/dataobj/builder.go", path, "path")
    eq("/Users/foo/workspace/gold-pond", root, "root")
end)

test("worktree commit diffview URI resolves to worktree root", function()
    setup_worktree_gitdir(tmp_main, "feature-branch", "/home/user/work/feature-branch")
    local path, root = util.resolve_file_path(
        "diffview://" .. tmp_main .. "/.git/worktrees/feature-branch/abc1234def0/src/bar.lua"
    )
    eq("/home/user/work/feature-branch/src/bar.lua", path, "path")
    eq("/home/user/work/feature-branch", root, "root")
end)

test("worktree stage 2 diffview URI resolves to worktree root", function()
    setup_worktree_gitdir(tmp_main, "my-wt", "/Users/foo/my-wt")
    local path, root = util.resolve_file_path(
        "diffview://" .. tmp_main .. "/.git/worktrees/my-wt/:2:/src/conflict.lua"
    )
    eq("/Users/foo/my-wt/src/conflict.lua", path, "path")
    eq("/Users/foo/my-wt", root, "root")
end)

test("worktree with deeply nested file path", function()
    setup_worktree_gitdir(tmp_main, "deep-wt", "/Users/foo/deep-wt")
    local path, root = util.resolve_file_path(
        "diffview://" .. tmp_main .. "/.git/worktrees/deep-wt/:0:/lua/tw/agent/init.lua"
    )
    eq("/Users/foo/deep-wt/lua/tw/agent/init.lua", path, "path")
    eq("/Users/foo/deep-wt", root, "root")
end)

test("worktree fallback to main repo root when gitdir unreadable", function()
    -- Use a worktree name that has no gitdir file set up
    local path, root = util.resolve_file_path(
        "diffview://" .. tmp_main .. "/.git/worktrees/no-gitdir/:0:/src/bar.lua"
    )
    eq(tmp_main .. "/src/bar.lua", path, "path")
    eq(tmp_main, root, "root")
end)

test("worktree with full SHA in commit URI", function()
    setup_worktree_gitdir(tmp_main, "sha-wt", "/Users/foo/sha-wt")
    local path, root = util.resolve_file_path(
        "diffview://"
            .. tmp_main
            .. "/.git/worktrees/sha-wt/abc1234def0abc1234def0abc1234def0abc1234d/src/bar.lua"
    )
    eq("/Users/foo/sha-wt/src/bar.lua", path, "path")
    eq("/Users/foo/sha-wt", root, "root")
end)

-- Clean up test fixtures
cleanup_worktree_gitdir(tmp_main)

print()
print(string.format("Results: %d passed, %d failed, %d total", pass_count, fail_count, pass_count + fail_count))

if fail_count > 0 then
    os.exit(1)
end
