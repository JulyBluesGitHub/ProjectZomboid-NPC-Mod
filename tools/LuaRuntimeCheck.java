import java.io.Reader;
import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

public final class LuaRuntimeCheck {
    private LuaRuntimeCheck() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            System.err.println("Usage: LuaRuntimeCheck <lua-file> [<lua-file> ...]");
            System.exit(2);
        }

        Class<?> platformClass = Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Class<?> platformInterface = Class.forName("se.krka.kahlua.vm.Platform");
        Class<?> tableClass = Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> threadClass = Class.forName("se.krka.kahlua.vm.KahluaThread");

        Object platform = platformClass.getMethod("getInstance").invoke(null);
        Object environment = platformClass.getMethod("newEnvironment").invoke(platform);
        Constructor<?> threadConstructor = threadClass.getConstructor(platformInterface, tableClass);
        Object thread = threadConstructor.newInstance(platform, environment);
        threadClass.getField("debugOwnerThread").set(thread, Thread.currentThread());
        Method call = threadClass.getMethod("call", Object.class, Object[].class);
        Method load = findLoadMethod();

        for (String argument : args) {
            Path file = Path.of(argument).toAbsolutePath().normalize();
            try (Reader reader = Files.newBufferedReader(file, StandardCharsets.UTF_8)) {
                Object closure = load.invoke(null, reader, file.toString().replace('\\', '/'), environment);
                call.invoke(thread, new Object[] { closure, new Object[0] });
                System.out.println("PASS runtime " + file.getFileName());
            } catch (Throwable error) {
                Throwable cause = unwrap(error);
                System.err.println("FAIL runtime " + file + ": " + cause.getMessage());
                cause.printStackTrace(System.err);
                System.exit(1);
            }
        }
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
        Throwable current = error;
        while (current instanceof InvocationTargetException invocation && invocation.getCause() != null) {
            current = invocation.getCause();
        }
        return current;
    }
}
