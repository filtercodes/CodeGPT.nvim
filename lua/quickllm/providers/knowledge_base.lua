local curl = require("plenary.curl")
local Utils = require("quickllm.utils")
local Api = require("quickllm.api")
local ContextEngine = require("quickllm.context_engine")

local KB = {}

-- State for background indexing
local is_indexing = false
local last_progress_time = 0
local index_stats = {
    total = 0,
    processed = 0,
    start_time = 0
}

---Helper to run SQL commands via the sqlite3 CLI.
---Supports loading the vector extension and running multiple statements in one session.
---@param sql string The SQL query or multiple statements.
---@param load_vec boolean? Whether to attempt loading the sqlite-vec extension.
---@return table results The output lines from the command.
function KB.run_sql(sql, load_vec)
    local db_path = vim.g.quickllm_kb_db_path
    local vec_path = vim.g.quickllm_kb_sqlite_vec_path
    
    local function execute()
        local tmp = vim.fn.tempname()
        local f = io.open(tmp, "w")
        if f then
            if load_vec and vec_path ~= "" and vim.fn.filereadable(vec_path) == 1 then
                f:write(string.format(".load %s\n", vec_path))
            end
            f:write(sql)
            f:close()
            
            local cmd = string.format("sqlite3 %s < %s", db_path, tmp)
            local res = vim.fn.systemlist(cmd)
            os.remove(tmp)
            return res
        end
        return {}
    end

    -- RETRY LOGIC: SQLite can lock the database during background indexing.
    local retries = 3
    local delay = 100 -- ms
    for i = 1, retries do
        local results = execute()
        local output_str = table.concat(results, " ")
        if not output_str:lower():find("database is locked") then
            return results
        end
        if i < retries then
            vim.wait(delay)
        end
    end
    
    vim.notify("KB Error: SQLite database is locked after multiple retries.", vim.log.levels.ERROR)
    return {}
end

---Initializes the SQLite database with the hierarchical schema.
function KB.init_db()
    if vim.fn.executable("sqlite3") ~= 1 then
        vim.notify("Knowledge Base Error: 'sqlite3' executable not found.", vim.log.levels.ERROR)
        return false
    end

    -- Relational Schema
    local schema = [[
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY,
            filepath TEXT UNIQUE,
            hash TEXT,
            summary_text TEXT,
            schema_links TEXT,
            contradictions TEXT,
            last_updated INTEGER
        );
        CREATE TABLE IF NOT EXISTS chunk_content (
            id INTEGER PRIMARY KEY,
            document_id INTEGER,
            content TEXT,
            FOREIGN KEY(document_id) REFERENCES documents(id)
        );
    ]]
    
    KB.run_sql(schema)

    local vec_path = vim.g.quickllm_kb_sqlite_vec_path
    if vec_path ~= "" and vim.fn.filereadable(vec_path) == 1 then
        local dim = vim.g.quickllm_kb_embedding_dimension or 768
        local vec_schema = string.format([[
            CREATE VIRTUAL TABLE IF NOT EXISTS summaries_vec USING vec0(
                id INTEGER PRIMARY KEY,
                embedding FLOAT[%d]
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_vec USING vec0(
                id INTEGER PRIMARY KEY,
                embedding FLOAT[%d]
            );
        ]], dim, dim)
        KB.run_sql(vec_schema, true)
    end
    
    return true
end

---Calls the LLM to act as a Librarian and summarize the document.
function KB.get_librarian_metadata(content, cb)
    local kb_folder = vim.g.quickllm_kb_folder
    local schema_path = kb_folder .. "/schema.md"
    local schema_content = ""
    if vim.fn.filereadable(schema_path) == 1 then
        schema_content = table.concat(vim.fn.readfile(schema_path), "\n")
    end

    local prompt = string.format([[
You are the Knowledge Base Librarian. Read the following document and the provided schema.
Output a JSON object with strictly these keys:
- summary: A dense, 3-sentence summary of the core concepts.
- schema_links: An array of strings listing concepts from the schema this document relates to.
- contradictions: Any notes on where this document differs from known schema rules.

SCHEMA:
%s

DOCUMENT:
%s
]], schema_content, content)

    local overrides = { provider = "ollama", model = vim.g.quickllm_kb_embedding_model:match("([^:]+)") or "qwen3" }
    local Providers = require("quickllm.providers")
    local CommandsList = require("quickllm.commands_list")
    local provider = Providers.get_provider(overrides)
    local cmd_opts = CommandsList.get_cmd_opts("chat", overrides)
    
    cmd_opts.extra_params = vim.tbl_extend("force", cmd_opts.extra_params or {}, { format = "json" })

    provider.make_call({
        model = cmd_opts.model,
        messages = {{role = "user", content = prompt}},
        stream = false,
        format = "json"
    }, prompt, function(lines)
        local response = table.concat(lines, "\n")
        local ok, json = pcall(vim.json.decode, response)
        if ok and json then
            cb(json)
        else
            cb(nil, "Librarian failed to return valid JSON")
        end
    end, -1)
end

---Generates an embedding for text.
function KB.generate_embedding(text, cb)
    local url = (vim.g.quickllm_ollama_url or "http://localhost:11434") .. "/api/embeddings"
    local model = vim.g.quickllm_kb_embedding_model
    
    curl.post(url, {
        body = vim.json.encode({ model = model, prompt = text }),
        callback = function(res)
            if res.status ~= 200 then
                vim.schedule(function() cb(nil, "Embedding Error: " .. res.status) end)
                return
            end
            local ok, json = pcall(vim.json.decode, res.body)
            if ok and json and json.embedding then
                vim.schedule(function() cb(json.embedding) end)
            else
                vim.schedule(function() cb(nil, "Failed to parse embedding response") end)
            end
        end,
        on_error = function(err)
            vim.schedule(function() cb(nil, "Curl Error: " .. tostring(err)) end)
        end
    })
end

---Main indexing entry point.
function KB.index_kb()
    local now = os.time()
    
    -- SAFETY: If indexing has been "active" for more than 5 minutes without progress, 
    -- assume it crashed and allow reset.
    if is_indexing and (now - last_progress_time < 300) then
        vim.notify("Indexing already in progress.", vim.log.levels.WARN)
        return
    end

    if not KB.init_db() then return end

    local kb_folder = vim.g.quickllm_kb_folder
    local files = vim.fn.globpath(kb_folder, "**/*.md", true, true)
    if #files == 0 then
        vim.notify("No Markdown files found in KB folder.", vim.log.levels.INFO)
        return
    end

    is_indexing = true
    last_progress_time = now
    index_stats.total = #files
    index_stats.processed = 0
    index_stats.start_time = vim.loop.now()

    vim.notify(string.format("Starting Knowledge Base indexing (%d files, Mode: %s)...", #files, vim.g.quickllm_kb_style), vim.log.levels.INFO)

    KB.process_next_file(files, 1)
end

---Check if a file needs re-indexing.
function KB.needs_indexing(path)
    local current_hash = ContextEngine.get_file_hash(path)
    if not current_hash then return false end

    local results = KB.run_sql(string.format("SELECT hash FROM documents WHERE filepath = '%s';", path))
    return not (#results > 0 and results[1] == current_hash)
end

---Orchestrates the one-pass indexing for a file.
function KB.process_next_file(files, index)
    if index > #files then
        is_indexing = false
        vim.notify(string.format("Indexing Complete! Processed %d files.", #files), vim.log.levels.INFO)
        return
    end

    -- Heartbeat for the lock safety
    last_progress_time = os.time()

    local path = files[index]
    if not KB.needs_indexing(path) then
        index_stats.processed = index
        KB.process_next_file(files, index + 1)
        return
    end

    local content_lines = vim.fn.readfile(path)
    local content = table.concat(content_lines, "\n")
    local hash = ContextEngine.get_file_hash(path)
    local style = vim.g.quickllm_kb_style
    
    -- IMPROVED CHUNKING: Split by headers but keep them in the chunk
    local chunks = {}
    local current_chunk = ""
    for _, line in ipairs(content_lines) do
        if line:match("^#") and current_chunk ~= "" then
            table.insert(chunks, vim.trim(current_chunk))
            current_chunk = line .. "\n"
        else
            current_chunk = current_chunk .. line .. "\n"
        end
    end
    if current_chunk ~= "" then table.insert(chunks, vim.trim(current_chunk)) end
    if #chunks == 0 then table.insert(chunks, content) end

    -- ATOMIC CLEANUP: Reverse order to avoid orphans
    local cleanup_sql = string.format([[
        BEGIN TRANSACTION;
        DELETE FROM chunks_vec WHERE id IN (SELECT c.id FROM chunk_content c JOIN documents d ON c.document_id = d.id WHERE d.filepath = '%s');
        DELETE FROM summaries_vec WHERE id IN (SELECT id FROM documents WHERE filepath = '%s');
        DELETE FROM chunk_content WHERE document_id IN (SELECT id FROM documents WHERE filepath = '%s');
        DELETE FROM documents WHERE filepath = '%s';
        COMMIT;
    ]], path, path, path, path)
    KB.run_sql(cleanup_sql, true)

    local function finalize_file(metadata)
        -- 1. Insert Document and get ID (In same session)
        local summary = metadata and metadata.summary:gsub("'", "''") or ""
        local links = metadata and vim.json.encode(metadata.schema_links) or "[]"
        local contradictions = metadata and metadata.contradictions:gsub("'", "''") or ""
        
        local doc_sql = string.format([[
            INSERT INTO documents (filepath, hash, summary_text, schema_links, contradictions, last_updated)
            VALUES ('%s', '%s', '%s', '%s', '%s', %d);
            SELECT last_insert_rowid();
        ]], path, hash, summary, links, contradictions, os.time())
        
        local doc_id_res = KB.run_sql(doc_sql)
        local doc_id = tonumber(doc_id_res[1])

        -- 2. Parallel Embedding & Batch Storage
        local embeddings = {}
        local processed_count = 0
        local total_targets = #chunks + ( (style == "complex" and summary ~= "") and 1 or 0 )

        local function check_completion()
            processed_count = processed_count + 1
            if processed_count >= total_targets then
                -- All embeddings ready! Build one massive batch SQL string
                local batch_sqls = { "BEGIN TRANSACTION;" }
                
                -- Summary Vector
                if style == "complex" and embeddings["summary"] then
                    table.insert(batch_sqls, string.format(
                        "INSERT INTO summaries_vec (id, embedding) VALUES (%d, vec_f32('%s'));",
                        doc_id, vim.json.encode(embeddings["summary"])
                    ))
                end

                -- Chunks and Vectors
                for i, chunk_text in ipairs(chunks) do
                    local escaped_text = chunk_text:gsub("'", "''")
                    table.insert(batch_sqls, string.format(
                        "INSERT INTO chunk_content (document_id, content) VALUES (%d, '%s');",
                        doc_id, escaped_text
                    ))
                    if embeddings[i] then
                        table.insert(batch_sqls, string.format(
                            "INSERT INTO chunks_vec (id, embedding) VALUES (last_insert_rowid(), vec_f32('%s'));",
                            vim.json.encode(embeddings[i])
                        ))
                    end
                end
                
                table.insert(batch_sqls, "COMMIT;")
                KB.run_sql(table.concat(batch_sqls, "\n"), true)

                index_stats.processed = index
                vim.defer_fn(function() KB.process_next_file(files, index + 1) end, 10)
            end
        end

        -- Trigger async embeddings
        if style == "complex" and summary ~= "" then
            KB.generate_embedding(summary, function(emb)
                embeddings["summary"] = emb
                check_completion()
            end)
        end

        for i, chunk_text in ipairs(chunks) do
            KB.generate_embedding(chunk_text, function(emb)
                embeddings[i] = emb
                check_completion()
            end)
        end
    end

    if style == "complex" then
        KB.get_librarian_metadata(content, function(meta, err)
            if err then vim.notify("Librarian Error: " .. err, vim.log.levels.WARN) end
            finalize_file(meta)
        end)
    else
        finalize_file(nil)
    end
end

---Provider entry point for Search.
function KB.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    return { query = command_args }, command_args
end

---Performs Hybrid Hierarchical Search.
function KB.make_call(payload, user_msg, cb, bufnr)
    local query = payload.query
    local style = vim.g.quickllm_kb_style
    local vec_path = vim.g.quickllm_kb_sqlite_vec_path
    local has_vec = vec_path ~= "" and vim.fn.filereadable(vec_path) == 1

    KB.generate_embedding(query, function(query_vec, err)
        local results = {}
        
        if not err and query_vec and has_vec then
            local vec_json = vim.json.encode(query_vec)
            
            if style == "complex" then
                -- 1. Search Summaries (The Map) with Links
                -- We use a separator for multi-column parsing from CLI
                local summary_sql = string.format([[
                    SELECT summary_text || '@@@' || schema_links || '@@@' || filepath
                    FROM documents d
                    JOIN summaries_vec s ON d.id = s.id
                    WHERE s.embedding MATCH vec_f32('%s') AND k = 2
                    ORDER BY distance;
                ]], vec_json)
                local map_data = KB.run_sql(summary_sql, true)
                
                if #map_data > 0 then 
                    table.insert(results, "--- THE MAP (Conceptual Overview) ---")
                    for _, row in ipairs(map_data) do
                        local parts = vim.split(row, "@@@", { plain = true })
                        local summary = parts[1] or ""
                        local links = parts[2] or "[]"
                        local path = parts[3] or ""
                        
                        table.insert(results, "> " .. summary)
                        table.insert(results, "> Links: " .. links)
                        table.insert(results, "> SOURCE: " .. path)
                        table.insert(results, "")
                    end
                end
            end

            -- 2. Search Chunks (The Territory) with File Paths for 'gf'
            local chunk_sql = string.format([[
                SELECT d.filepath || '@@@' || c.content 
                FROM chunk_content c
                JOIN documents d ON c.document_id = d.id
                JOIN chunks_vec v ON c.id = v.id
                WHERE v.embedding MATCH vec_f32('%s') AND k = 5
                ORDER BY distance;
            ]], vec_json)
            local territory_data = KB.run_sql(chunk_sql, true)
            
            if #territory_data > 0 then 
                table.insert(results, "\n--- THE TERRITORY (Specific Chunks) ---")
                for _, row in ipairs(territory_data) do
                    local parts = vim.split(row, "@@@", { plain = true })
                    local path = parts[1] or "Unknown"
                    local chunk = parts[2] or ""
                    
                    table.insert(results, string.format("SOURCE: %s\n%s", path, chunk))
                    table.insert(results, "---")
                end
            end
        else
            -- Keyword Fallback
            local kw_sql = string.format("SELECT content FROM chunk_content WHERE content LIKE '%%%s%%' LIMIT 5;", query:gsub("'", "''"))
            results = KB.run_sql(kw_sql)
        end

        local final_text = #results > 0 and table.concat(results, "\n") or "No relevant knowledge found."
        cb.on_chunk("[System: Knowledge Retrieval]\n\n" .. final_text, false)
        cb.on_complete(final_text)
    end)
end

---Saves content (selection or buffer) to a new markdown file in the KB folder.
---@param filename string The target filename.
---@param selection string? The selected text (optional).
function KB.save_to_wiki(filename, selection)
    local kb_folder = vim.g.quickllm_kb_folder
    if vim.fn.isdirectory(kb_folder) == 0 then
        vim.fn.mkdir(kb_folder, "p")
    end

    -- Add .md extension if missing
    if not filename:match("%.md$") then
        filename = filename .. ".md"
    end

    local path = kb_folder .. "/" .. filename
    local content = selection
    
    if not content or content == "" then
        -- Use entire buffer if no selection
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        content = table.concat(lines, "\n")
    end

    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
        vim.notify("Saved to Wiki: " .. path, vim.log.levels.INFO)
        -- Trigger indexing for this specific file
        KB.process_next_file({ path }, 1)
    else
        vim.notify("Error: Could not write to " .. path, vim.log.levels.ERROR)
    end
end

return KB
