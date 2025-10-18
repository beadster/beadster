export async function GET() {
  return new Response(JSON.stringify({ status: "ok", message: "API endpoint works" }), {
    headers: {
      "Content-Type": "application/json",
    },
  });
}
