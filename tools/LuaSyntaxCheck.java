import java.io.IOException;
import java.io.Reader;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;

public final class LuaSyntaxCheck {
    private LuaSyntaxCheck() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            System.err.println("Usage: LuaSyntaxCheck <lua-root>");
            System.exit(2);
        }

        Path root = Path.of(args[0]).toAbsolutePath().normalize();
        if (!Files.isDirectory(root)) {
            System.err.println("Lua root does not exist: " + root);
            System.exit(2);
        }

        List<Path> files = findLuaFiles(root);
        Object environment = createEnvironment();
        Method loadMethod = findLoadMethod();
        List<String> failures = new ArrayList<>();

        for (Path file : files) {
            String chunkName = root.relativize(file).toString().replace('\\', '/');
            try (Reader reader = Files.newBufferedReader(file, StandardCharsets.UTF_8)) {
                loadMethod.invoke(null, reader, chunkName, environment);
                System.out.println("PASS " + chunkName);
            } catch (Throwable error) {
                Throwable cause = unwrap(error);
                failures.add(chunkName + ": " + cause.getMessage());
                System.err.println("FAIL " + chunkName + ": " + cause.getMessage());
            }
        }

        if (!failures.isEmpty()) {
            System.err.println(failures.size() + " Lua file(s) failed Kahlua compilation.");
            System.exit(1);
        }

        System.out.println("Compiled " + files.size() + " Lua file(s) with Project Zomboid's Kahlua compiler.");
    }

    private static Object createEnvironment() throws Exception {
        Class<?> platformClass = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform = platformClass.getMethod("getInstance").invoke(null);
        // Parsing only needs an environment table. newEnvironment() also executes
        // stdlib.lua from the process working directory, which would couple this
        // syntax check to launch location rather than the target compiler.
        return platformClass.getMethod("newTable").invoke(platform);
    }

    private static Method findLoadMethod() throws Exception {
        Class<?> compilerClass = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler");
        for (Method method : compilerClass.getMethods()) {
            Class<?>[] parameters = method.getParameterTypes();
            if (method.getName().equals("loadis")
                && parameters.length == 3
                && Reader.class.isAssignableFrom(parameters[0])
                && parameters[1] == String.class) {
                return method;
            }
        }
        throw new NoSuchMethodException("LuaCompiler.loadis(Reader, String, KahluaTable)");
    }

    private static Throwable unwrap(Throwable error) {
        if (error instanceof InvocationTargetException invocation && invocation.getCause() != null) {
            return invocation.getCause();
        }
        return error;
    }

    private static List<Path> findLuaFiles(Path root) throws IOException {
        try (Stream<Path> stream = Files.walk(root)) {
            return stream
                .filter(Files::isRegularFile)
                .filter(path -> path.getFileName().toString().endsWith(".lua"))
                .sorted(Comparator.comparing(Path::toString))
                .toList();
        }
    }
}
