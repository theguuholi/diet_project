defmodule Mix.Tasks.Coverage.Index do
  @moduledoc """
  Generates an index.html file for the coverage reports.

  ## Usage

      mix test --cover && mix coverage.index

  Or use the precommit alias which includes both.
  """

  use Mix.Task

  @shortdoc "Generates an index.html for coverage reports"

  @impl Mix.Task
  def run(_args) do
    cover_dir = "cover"

    unless File.dir?(cover_dir) do
      Mix.shell().error("No coverage directory found. Run 'mix test --cover' first.")
      System.halt(1)
    end

    # Get all HTML files except index.html
    html_files =
      "#{cover_dir}/Elixir.*.html"
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()

    if html_files == [] do
      Mix.shell().error("No coverage HTML files found in #{cover_dir}/")
      System.halt(1)
    end

    # Parse coverage from each file
    module_results =
      html_files
      |> Enum.map(fn file ->
        module_name = file |> String.replace_suffix(".html", "")
        path = Path.join(cover_dir, file)
        {module_name, file, parse_coverage(path)}
      end)
      |> Enum.filter(fn {_, _, coverage} -> coverage != nil end)

    # Calculate totals
    total_covered =
      module_results
      |> Enum.map(fn {_, _, {c, _}} -> c end)
      |> Enum.sum()

    total_lines =
      module_results
      |> Enum.map(fn {_, _, {_, t}} -> t end)
      |> Enum.sum()

    total_percentage = if total_lines == 0, do: 100.0, else: total_covered / total_lines * 100

    # Generate index
    html = generate_html(module_results, total_covered, total_lines, total_percentage)
    index_path = Path.join(cover_dir, "index.html")
    File.write!(index_path, html)

    Mix.shell().info("✓ Coverage index generated: #{index_path}")

    Mix.shell().info(
      "  Overall coverage: #{Float.round(total_percentage, 2)}% (#{total_covered}/#{total_lines} lines)"
    )

    Mix.shell().info("  Open in browser: open #{index_path}")
  end

  defp parse_coverage(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        # Count <tr class="hit"> and <tr class="miss"> in the HTML
        hit_count =
          content
          |> String.split("<tr class=\"hit\">")
          |> length()
          |> Kernel.-(1)

        miss_count =
          content
          |> String.split("<tr class=\"miss\">")
          |> length()
          |> Kernel.-(1)

        total = hit_count + miss_count

        if total > 0 do
          {hit_count, total}
        else
          nil
        end

      {:error, _} ->
        nil
    end
  end

  defp generate_html(module_results, total_covered, total_lines, total_percentage) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Test Coverage Report</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          background: #f8f9fa;
          padding: 2rem;
          line-height: 1.6;
        }
        .container {
          max-width: 1400px;
          margin: 0 auto;
          background: white;
          border-radius: 12px;
          overflow: hidden;
          box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
        }
        .header {
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          padding: 3rem 2rem;
        }
        h1 {
          font-size: 2.5rem;
          margin-bottom: 1rem;
          font-weight: 700;
        }
        .summary {
          font-size: 1.125rem;
          opacity: 0.95;
        }
        .summary strong {
          font-size: 3.5rem;
          display: block;
          margin-top: 1rem;
          font-weight: 700;
          letter-spacing: -0.02em;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 2rem;
          margin-top: 1.5rem;
        }
        .stat {
          display: flex;
          flex-direction: column;
        }
        .stat-label {
          font-size: 0.875rem;
          opacity: 0.9;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          font-weight: 500;
        }
        .stat-value {
          font-size: 1.75rem;
          font-weight: 600;
          margin-top: 0.25rem;
        }
        .content {
          padding: 0;
        }
        .filters {
          padding: 1.5rem 2rem;
          background: #f8f9fa;
          border-bottom: 1px solid #dee2e6;
        }
        .search-box {
          width: 100%;
          max-width: 500px;
          padding: 0.75rem 1rem;
          font-size: 1rem;
          border: 2px solid #dee2e6;
          border-radius: 8px;
          transition: all 0.2s;
        }
        .search-box:focus {
          outline: none;
          border-color: #667eea;
          box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        table {
          width: 100%;
          border-collapse: collapse;
        }
        thead {
          background: #f8f9fa;
          position: sticky;
          top: 0;
          z-index: 10;
        }
        th {
          text-align: left;
          padding: 1rem 2rem;
          font-weight: 600;
          color: #495057;
          border-bottom: 2px solid #dee2e6;
          font-size: 0.875rem;
          text-transform: uppercase;
          letter-spacing: 0.05em;
          cursor: pointer;
          user-select: none;
          transition: background 0.2s;
        }
        th:hover {
          background: #e9ecef;
        }
        th.sortable::after {
          content: ' ↕';
          opacity: 0.3;
          font-size: 0.875rem;
        }
        th.sorted-asc::after {
          content: ' ↑';
          opacity: 1;
        }
        th.sorted-desc::after {
          content: ' ↓';
          opacity: 1;
        }
        td {
          padding: 1rem 2rem;
          border-bottom: 1px solid #f1f3f5;
        }
        tbody tr {
          transition: all 0.15s;
        }
        tbody tr:hover {
          background: #f8f9fa;
          transform: translateX(4px);
        }
        a {
          color: #667eea;
          text-decoration: none;
          font-weight: 500;
          transition: color 0.2s;
        }
        a:hover {
          color: #764ba2;
          text-decoration: underline;
        }
        .percentage {
          font-weight: 600;
          padding: 0.375rem 0.875rem;
          border-radius: 6px;
          display: inline-block;
          min-width: 70px;
          text-align: center;
          font-size: 0.875rem;
        }
        .high { background: #d4edda; color: #155724; }
        .medium { background: #fff3cd; color: #856404; }
        .low { background: #f8d7da; color: #721c24; }
        .footer {
          padding: 1.5rem 2rem;
          background: #f8f9fa;
          border-top: 1px solid #dee2e6;
          text-align: center;
          color: #6c757d;
          font-size: 0.875rem;
        }
        .empty {
          padding: 3rem 2rem;
          text-align: center;
          color: #6c757d;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>📊 Test Coverage Report</h1>
          <div class="summary">
            <strong>#{Float.round(total_percentage, 2)}%</strong>
            <div class="stats">
              <div class="stat">
                <span class="stat-label">Total Coverage</span>
                <span class="stat-value">#{total_covered} / #{total_lines} lines</span>
              </div>
              <div class="stat">
                <span class="stat-label">Modules Analyzed</span>
                <span class="stat-value">#{length(module_results)}</span>
              </div>
              <div class="stat">
                <span class="stat-label">Status</span>
                <span class="stat-value">#{if total_percentage >= 93.5, do: "✓ Passing", else: "✗ Below Threshold"}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="content">
          <div class="filters">
            <input type="text" id="search" class="search-box" placeholder="Search modules...">
          </div>

          <table id="coverage-table">
            <thead>
              <tr>
                <th class="sortable" data-sort="module">Module</th>
                <th class="sortable" data-sort="covered">Lines Covered</th>
                <th class="sortable" data-sort="total">Total Lines</th>
                <th class="sortable" data-sort="percentage">Coverage %</th>
              </tr>
            </thead>
            <tbody>
              #{Enum.map_join(module_results, "\n", fn {module_name, file_name, {covered, total}} ->
      percentage = if total == 0, do: 100.0, else: covered / total * 100
      percentage_class = cond do
        percentage >= 80 -> "high"
        percentage >= 60 -> "medium"
        true -> "low"
      end

      """
      <tr data-module="#{String.downcase(module_name)}">
        <td><a href="#{file_name}">#{module_name}</a></td>
        <td>#{covered}</td>
        <td>#{total}</td>
        <td><span class="percentage #{percentage_class}">#{Float.round(percentage, 2)}%</span></td>
      </tr>
      """
    end)}
            </tbody>
          </table>
        </div>

        <div class="footer">
          Generated on #{DateTime.utc_now() |> DateTime.to_string()} •
          Run <code>mix test --cover && mix coverage.index</code> to update
        </div>
      </div>

      <script>
        // Search functionality
        const searchInput = document.getElementById('search');
        const table = document.getElementById('coverage-table');
        const rows = table.querySelectorAll('tbody tr');

        searchInput.addEventListener('input', (e) => {
          const searchTerm = e.target.value.toLowerCase();
          rows.forEach(row => {
            const module = row.dataset.module;
            row.style.display = module.includes(searchTerm) ? '' : 'none';
          });
        });

        // Sort functionality
        const headers = table.querySelectorAll('th.sortable');
        let currentSort = { column: null, direction: 'asc' };

        headers.forEach(header => {
          header.addEventListener('click', () => {
            const sortType = header.dataset.sort;
            const direction = currentSort.column === sortType && currentSort.direction === 'asc' ? 'desc' : 'asc';

            // Update header classes
            headers.forEach(h => {
              h.classList.remove('sorted-asc', 'sorted-desc');
            });
            header.classList.add(direction === 'asc' ? 'sorted-asc' : 'sorted-desc');

            // Sort rows
            const rowsArray = Array.from(rows);
            rowsArray.sort((a, b) => {
              let aVal, bVal;
              const cells = {
                a: a.querySelectorAll('td'),
                b: b.querySelectorAll('td')
              };

              switch(sortType) {
                case 'module':
                  aVal = cells.a[0].textContent.toLowerCase();
                  bVal = cells.b[0].textContent.toLowerCase();
                  break;
                case 'covered':
                  aVal = parseInt(cells.a[1].textContent);
                  bVal = parseInt(cells.b[1].textContent);
                  break;
                case 'total':
                  aVal = parseInt(cells.a[2].textContent);
                  bVal = parseInt(cells.b[2].textContent);
                  break;
                case 'percentage':
                  aVal = parseFloat(cells.a[3].textContent);
                  bVal = parseFloat(cells.b[3].textContent);
                  break;
              }

              if (direction === 'asc') {
                return aVal > bVal ? 1 : -1;
              } else {
                return aVal < bVal ? 1 : -1;
              }
            });

            const tbody = table.querySelector('tbody');
            rowsArray.forEach(row => tbody.appendChild(row));

            currentSort = { column: sortType, direction };
          });
        });
      </script>
    </body>
    </html>
    """
  end
end
