# Common Lisp Ecosystem Catalog

This catalog records an initial curated set of high-quality Common Lisp libraries using live
network-sourced information, in line with the project constitution.

## Refresh Policy

- Catalog refresh date: 2026-03-29
- Primary curation source: https://github.com/CodyReichert/awesome-cl
- Availability and ecosystem cross-check source: https://quickdocs.org/
- Upstream update field policy: prefer the latest observed repository commit signal from the
  canonical upstream page. When the fetched source only exposed a relative time signal, that
  relative value is recorded verbatim.

## Output Schema

Each entry includes:

- Library name
- Category
- Canonical access or download link
- Concise description
- Last observed upstream update
- Catalog refresh date
- Source(s) used

## Curated Entries

| Library | Category | Canonical link | Concise description | Last observed upstream update | Catalog refresh date | Source(s) |
| --- | --- | --- | --- | --- | --- | --- |
| Serapeum | Utilities | https://github.com/ruricolist/serapeum | Conservative utility library that complements Alexandria without redesigning Common Lisp. | last month | 2026-03-29 | awesome-cl, GitHub repo page |
| Dexador | HTTP client | https://github.com/fukamachi/dexador | Fast HTTP client with connection pooling and a condition-based error model. | 5 days ago | 2026-03-29 | awesome-cl, GitHub repo page |
| QURI | URI handling | https://github.com/fukamachi/quri | RFC 3986-oriented URI parsing and encoding library intended as a modern PURI replacement. | 5 months ago | 2026-03-29 | awesome-cl, GitHub repo page |
| Clack | Web application environment | https://github.com/fukamachi/clack | Rack/WSGI-style web application environment that abstracts Common Lisp web servers. | last month | 2026-03-29 | awesome-cl, GitHub repo page, Quickdocs |
| Hunchentoot | Web server | https://github.com/edicl/hunchentoot | Mature Common Lisp web server and toolkit with sessions, SSL, and dynamic site support. | 2 weeks ago | 2026-03-29 | awesome-cl, GitHub repo page |
| Spinneret | HTML generation | https://github.com/ruricolist/spinneret | Modern HTML5 generator focused on composability, readable output, and Common Lisp ergonomics. | 7 months ago | 2026-03-29 | awesome-cl, GitHub repo page |
| Djula | Templates | https://github.com/mmontone/djula | Common Lisp port of Django's template language for server-rendered web applications. | 6 months ago | 2026-03-29 | awesome-cl, GitHub repo page |
| Mito | ORM and migrations | https://github.com/fukamachi/mito | ORM with migrations, relationship helpers, and support for PostgreSQL, MySQL, and SQLite. | last month | 2026-03-29 | awesome-cl, GitHub repo page, Quickdocs |
| FiveAM | Testing | https://github.com/lispci/fiveam | Regression testing framework widely used for Common Lisp unit and integration tests. | Release 1.4.3 on 2024-05-30; latest observed repo commit 2 years ago | 2026-03-29 | awesome-cl, GitHub repo page |
| Clingon | CLI | https://github.com/dnaeon/clingon | Rich command-line options parser with subcommands, generated help, and shell completion support. | last month | 2026-03-29 | awesome-cl, GitHub repo page |
| Jzon | JSON | https://github.com/Zulu-Inuoe/jzon | Correct and safety-oriented JSON reader and writer with strong RFC 8259 compliance and sane defaults. | last month | 2026-03-29 | awesome-cl, GitHub repo page |
| Shasht | JSON | https://github.com/yitzchak/shasht | Fast JSON reader and writer designed for strong round-trip behavior and Jupyter-oriented interoperability. | 4 months ago | 2026-03-29 | awesome-cl, GitHub repo page |
| CL-DBI | Database interface | https://github.com/fukamachi/cl-dbi | Database-independent SQL interface that unifies SQLite, PostgreSQL, and MySQL access behind one API. | last month | 2026-03-29 | awesome-cl, GitHub repo page |
| SxQL | SQL generation | https://github.com/fukamachi/sxql | Mature SQL DSL and query composer for building immutable, composable SQL statements in Common Lisp. | 3 months ago | 2026-03-29 | awesome-cl, GitHub repo page |
| local-time | Date and time | https://github.com/dlowe-net/local-time | Widely used date and time manipulation library based on Erik Naggum's time-handling work. | 2 weeks ago | 2026-03-29 | awesome-cl, Quickdocs, GitHub repo page |
| lparallel | Parallel programming | https://github.com/sharplispers/lparallel | Parallel programming library with futures, promises, queues, and parallel collection operators. | 7 months ago | 2026-03-29 | awesome-cl, GitHub repo page |
| Sento | Actors and concurrency | https://github.com/mdbergmann/cl-gserver | Actor framework with agents, routers, tasks, futures, FSM support, and recent remoting capabilities. | 5 days ago | 2026-03-29 | awesome-cl, GitHub repo page |

## Selection Notes

- These entries are intentionally curated rather than exhaustive.
- The initial set emphasizes libraries that are broadly useful when building Common Lisp systems
  that may eventually interoperate with Python-backed adapters in this repository.
- Preference was given to projects that appear in community curation, have public documentation,
  and show credible maintenance signals.

## Next Expansion Targets

- Data formats: CXML, Plump, cl-yaml or active YAML successor
- Database and SQL: Postmodern, pgloader, cl-migratum
- Concurrency and distributed systems: BordeauxThreads, Calispel, ChanL
- Packaging and workflows: Quicklisp, Qlot, CLPM, OCICL
- Documentation and developer experience: Lem, SLIME, mgl-pax, Staple