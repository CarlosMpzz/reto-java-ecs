package demo;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public final class App {
    private static final int PORT = 8080;

    public static void main(String[] args) throws IOException {
        String revision = System.getenv().getOrDefault("APP_REVISION", "local");
        HttpServer server = HttpServer.create(new InetSocketAddress(PORT), 0);
        server.createContext("/", exchange -> handle(exchange, revision));
        Runtime.getRuntime().addShutdownHook(new Thread(() -> server.stop(1)));
        server.start();
        System.out.println("Servidor iniciado en el puerto " + PORT + " (revision " + revision + ")");
    }

    private static void handle(HttpExchange exchange, String revision) throws IOException {
        try (exchange) {
            if (!"GET".equals(exchange.getRequestMethod())) {
                exchange.getResponseHeaders().set("Allow", "GET");
                respond(exchange, 405, "Metodo no permitido");
                return;
            }

            switch (exchange.getRequestURI().getPath()) {
                case "/" -> respond(exchange, 200, "Hola mundo desde AWS ECS");
                case "/health" -> respond(exchange, 200, "OK");
                case "/version" -> respond(exchange, 200, revision);
                default -> respond(exchange, 404, "Ruta no encontrada");
            }
        }
    }

    private static void respond(HttpExchange exchange, int status, String text) throws IOException {
        byte[] body = (text + "\n").getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=utf-8");
        exchange.sendResponseHeaders(status, body.length);
        exchange.getResponseBody().write(body);
    }
}
