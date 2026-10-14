# Ada JVM

This is a separate Ada project alongside the existing Java watchdog. It is an
early JVM implementation project, **not** a Java 25-compatible JVM yet.

## Current prototype

The prototype interprets a small subset of JVM method bytecode. It supports
`iconst_m1` through `iconst_5`, `bipush`, integer local-variable loads and
stores, `iinc`, integer arithmetic, integer conditional branches, `goto`, and
`ireturn`. It can also parse a Java class file and extract a selected static
method's `Code` attribute before interpreting it. Class loading, method
invocation, and the JVM runtime or Java standard library are not implemented.

The interpreter uses bounded operand-stack and local-variable arrays and Java
`int` arithmetic semantics for the supported operations. Branch targets are
range-checked, but bytecode is not verified and targets are not checked for
instruction boundaries. Input files are raw method-code bytes, not Java class
files, and are limited to 64 KiB by the command-line runner.

## Build and run

Install GNAT and `gprbuild`, then from this directory:

```sh
gprbuild -P ada_jvm.gpr
./build/bin/ada_jvm --self-test
./build/bin/ada_jvm method.code
```

`method.code` must contain a supported instruction sequence ending in
`ireturn`. To execute a supported method from a class file, provide its name
and JVM descriptor, for example:

```sh
./build/bin/ada_jvm --class-file Example.class calculate '()I'
```

Class files are limited to 16 MiB, and method bytecode to 65535 bytes. The
reader accepts class-file versions 45 through 69 and extracts static methods
only. It does not verify bytecode, resolve classes, or execute the complete JVM
instruction set. The runner prints the returned integer. `--self-test` runs
built-in interpreter checks.

## Java 25 compatibility roadmap

The target is **Java SE 25 runtime compatibility**, including the Java Virtual
Machine Specification (JVMS) and the Java SE 25 API specification. This project
is a runtime, not a Java source compiler: accepting Java 25 source syntax is
outside its scope. Compatibility includes class-file versions and features,
verification, linking and execution semantics, and the specified Java SE APIs;
support for only the class-file major version or a subset of bytecodes is not
full compatibility.

### Conformance strategy

Build a conformance suite from small Java programs and class files compiled
with a Java 25 JDK. Run each supported fixture both on this runtime and on an
independent Java 25 reference JVM, then compare specified observable behavior:
return values, output, exit status, and exception behavior. Include valid
fixtures as well as malformed or unsupported inputs, which must be rejected
safely rather than misinterpreted. Keep fixtures and expected outcomes
reproducible, and organize them by JVMS and Java SE API feature so gaps remain
visible. Use the official Java compatibility test suite when its terms and
availability permit; a local differential suite alone is not a certification.

Do not claim Java 25 compatibility until the implementation covers the defined
runtime and API scope and passes the applicable conformance suite. The current
prototype does not meet that bar: verification, class loading and linking,
most instructions, runtime data areas, exceptions, objects and arrays,
platform interfaces, garbage collection, and the Java SE library remain
unimplemented. Implementation and conformance testing must advance together
through these milestones.

### JVM-first implementation order

This Ada JVM is the first runtime target. Rust and C# implementations or ports
are deferred until the Ada runtime has a well-defined execution model and
conformance tests; they are not prerequisites for JVM progress. Advance the Ada
runtime in small, testable stages:

1. Grow the verified interpreter core with local-variable and control-flow
   coverage, then add bytecode verification against instruction boundaries and
   method limits.
2. Implement class loading, linking, method invocation, runtime data areas,
   exception handling, and the remaining JVMS execution semantics.
3. Add objects, arrays, garbage collection, platform integration, and Java SE
   APIs, validating each area with reference-JVM differential tests.

Passing the prototype self-tests demonstrates only the implemented subset; it
does not imply JVM or Java SE compatibility. Revisit Rust and C# only as
separately scoped follow-up projects after the Ada conformance gaps and
cross-runtime test fixtures are clearly established.
