from mcp.server.fastmcp import FastMCP

mcp = FastMCP("MCP Research Server", host="0.0.0.0", port=8080)


@mcp.tool()
def hello() -> str:
    """A simple hello tool for testing the MCP server pipeline."""
    print("hello tool called")
    return "Hello from MCP Research Server!"


if __name__ == "__main__":
    mcp.run(transport="sse")
