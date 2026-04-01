"use client";

import React, { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { AnimatePresence, motion } from "framer-motion";
import { ArrowRight, Check, Gamepad2, LogIn, Menu, RefreshCcw, UserPlus, X } from "lucide-react";
import { Canvas, useFrame, useThree } from "@react-three/fiber";
import * as THREE from "three";
import { cn } from "@/lib/utils";

type UniformValue = number[] | number[][] | number;

type Uniforms = Record<string, { value: UniformValue; type: string }>;

interface ShaderProps {
  source: string;
  uniforms: Uniforms;
  maxFps?: number;
}

interface SignInPageProps {
  className?: string;
}

interface DotMatrixProps {
  colors?: number[][];
  opacities?: number[];
  totalSize?: number;
  dotSize?: number;
  reverse?: boolean;
  animationSpeed?: number;
  center?: ("x" | "y")[];
}

export const CanvasRevealEffect = ({
  animationSpeed = 10,
  opacities = [0.3, 0.3, 0.3, 0.5, 0.5, 0.5, 0.8, 0.8, 0.8, 1],
  colors = [[0, 255, 255]],
  containerClassName,
  dotSize,
  showGradient = true,
  reverse = false,
}: {
  animationSpeed?: number;
  opacities?: number[];
  colors?: number[][];
  containerClassName?: string;
  dotSize?: number;
  showGradient?: boolean;
  reverse?: boolean;
}) => {
  return (
    <div className={cn("relative h-full w-full", containerClassName)}>
      <DotMatrix
        colors={colors}
        dotSize={dotSize ?? 3}
        opacities={opacities}
        reverse={reverse}
        animationSpeed={animationSpeed}
        center={["x", "y"]}
      />
      {showGradient && <div className="absolute inset-0 bg-gradient-to-t from-black to-transparent" />}
    </div>
  );
};

const DotMatrix = ({
  colors = [[255, 255, 255]],
  opacities = [0.04, 0.04, 0.04, 0.04, 0.04, 0.08, 0.08, 0.08, 0.08, 0.14],
  totalSize = 20,
  dotSize = 2,
  reverse = false,
  animationSpeed = 10,
  center = ["x", "y"],
}: DotMatrixProps) => {
  const uniforms = useMemo(() => {
    const palette = colors.length === 1 ? [colors[0], colors[0], colors[0], colors[0], colors[0], colors[0]] : colors.length === 2 ? [colors[0], colors[0], colors[0], colors[1], colors[1], colors[1]] : [colors[0], colors[0], colors[1], colors[1], colors[2], colors[2]];

    return {
      u_colors: { value: palette.map((c) => [c[0] / 255, c[1] / 255, c[2] / 255]), type: "uniform3fv" },
      u_opacities: { value: opacities, type: "uniform1fv" },
      u_total_size: { value: totalSize, type: "uniform1f" },
      u_dot_size: { value: dotSize, type: "uniform1f" },
      u_reverse: { value: reverse ? 1 : 0, type: "uniform1i" },
      u_animation_speed: { value: Math.max(animationSpeed / 20, 0.05), type: "uniform1f" },
    } satisfies Uniforms;
  }, [colors, opacities, totalSize, dotSize, reverse, animationSpeed]);

  const alignX = center.includes("x")
    ? "st.x -= abs(floor((mod(u_resolution.x, u_total_size) - u_dot_size) * 0.5));"
    : "";
  const alignY = center.includes("y")
    ? "st.y -= abs(floor((mod(u_resolution.y, u_total_size) - u_dot_size) * 0.5));"
    : "";

  return (
    <Shader
      source={`
        precision mediump float;
        in vec2 fragCoord;

        uniform float u_time;
        uniform float u_opacities[10];
        uniform vec3 u_colors[6];
        uniform float u_total_size;
        uniform float u_dot_size;
        uniform vec2 u_resolution;
        uniform float u_animation_speed;
        uniform int u_reverse;

        out vec4 fragColor;

        float PHI = 1.61803398874989484820459;
        float random(vec2 xy){ return fract(tan(distance(xy * PHI, xy) * 0.5) * xy.x); }

        void main() {
          vec2 st = fragCoord.xy;
          ${alignX}
          ${alignY}

          float opacity = step(0.0, st.x) * step(0.0, st.y);
          vec2 st2 = vec2(int(st.x / u_total_size), int(st.y / u_total_size));

          float frequency = 5.0;
          float seed = random(st2);
          float flicker = random(st2 * floor((u_time / frequency) + seed + frequency));

          opacity *= u_opacities[int(flicker * 10.0)];
          opacity *= 1.0 - step(u_dot_size / u_total_size, fract(st.x / u_total_size));
          opacity *= 1.0 - step(u_dot_size / u_total_size, fract(st.y / u_total_size));

          vec3 color = u_colors[int(seed * 6.0)];
          vec2 center_grid = u_resolution / 2.0 / u_total_size;
          float dist_from_center = distance(center_grid, st2);
          float max_grid_dist = distance(center_grid, vec2(0.0, 0.0));

          float intro = dist_from_center * 0.01 + random(st2) * 0.15;
          float outro = (max_grid_dist - dist_from_center) * 0.02 + random(st2 + 42.0) * 0.2;
          float offset = u_reverse == 1 ? outro : intro;

          if (u_reverse == 1) {
            opacity *= 1.0 - step(offset, u_time * u_animation_speed);
          } else {
            opacity *= step(offset, u_time * u_animation_speed);
          }

          fragColor = vec4(color, opacity);
          fragColor.rgb *= fragColor.a;
        }
      `}
      uniforms={uniforms}
      maxFps={60}
    />
  );
};

const ShaderMaterial = ({ source, uniforms, maxFps = 60 }: ShaderProps) => {
  const { size } = useThree();
  const ref = useRef<THREE.Mesh>(null);
  const lastFrame = useRef(0);

  useFrame(({ clock }) => {
    if (!ref.current) return;
    const now = clock.getElapsedTime();
    const minFrame = maxFps > 0 ? 1 / maxFps : 0;
    if (minFrame > 0 && now - lastFrame.current < minFrame) return;
    lastFrame.current = now;
    const material = ref.current.material as THREE.ShaderMaterial;
    material.uniforms.u_time.value = now;
  });

  const material = useMemo(
    () => {
      const preparedUniforms: Record<string, { value: unknown; type?: string }> = {};
      for (const [name, uniform] of Object.entries(uniforms)) {
        if (uniform.type === "uniform1f" || uniform.type === "uniform1i" || uniform.type === "uniform1fv") {
          preparedUniforms[name] = { value: uniform.value };
        } else if (uniform.type === "uniform2f") {
          preparedUniforms[name] = { value: new THREE.Vector2().fromArray(uniform.value as number[]) };
        } else if (uniform.type === "uniform3f") {
          preparedUniforms[name] = { value: new THREE.Vector3().fromArray(uniform.value as number[]) };
        } else if (uniform.type === "uniform3fv") {
          preparedUniforms[name] = {
            value: (uniform.value as number[][]).map((v) => new THREE.Vector3().fromArray(v)),
          };
        }
      }

      preparedUniforms.u_time = { value: 0 };
      preparedUniforms.u_resolution = { value: new THREE.Vector2(size.width * 2, size.height * 2) };

      return new THREE.ShaderMaterial({
        vertexShader: `
          precision mediump float;
          uniform vec2 u_resolution;
          out vec2 fragCoord;
          void main() {
            gl_Position = vec4(position.xy, 0.0, 1.0);
            fragCoord = (position.xy + vec2(1.0)) * 0.5 * u_resolution;
            fragCoord.y = u_resolution.y - fragCoord.y;
          }
        `,
        fragmentShader: source,
        uniforms: preparedUniforms,
        glslVersion: THREE.GLSL3,
        blending: THREE.CustomBlending,
        blendSrc: THREE.SrcAlphaFactor,
        blendDst: THREE.OneFactor,
      });
    },
    [size.width, size.height, source, uniforms],
  );

  useEffect(() => () => material.dispose(), [material]);

  return (
    <mesh ref={ref}>
      <planeGeometry args={[2, 2]} />
      <primitive object={material} attach="material" />
    </mesh>
  );
};

const Shader = ({ source, uniforms, maxFps = 60 }: ShaderProps) => (
  <Canvas className="absolute inset-0 h-full w-full">
    <ShaderMaterial source={source} uniforms={uniforms} maxFps={maxFps} />
  </Canvas>
);

const AnimatedNavLink = ({ href, children }: { href: string; children: React.ReactNode }) => (
  <a href={href} className="group relative inline-flex h-5 items-center overflow-hidden text-sm">
    <div className="flex flex-col transition-transform duration-300 ease-out group-hover:-translate-y-1/2">
      <span className="text-gray-300">{children}</span>
      <span className="text-white">{children}</span>
    </div>
  </a>
);

function MiniNavbar() {
  const [isOpen, setIsOpen] = useState(false);
  const headerShapeClass = isOpen ? "rounded-xl" : "rounded-full";

  const navLinks = [
    { label: "Manifesto", href: "#1" },
    { label: "Careers", href: "#2" },
    { label: "Discover", href: "#3" },
  ];

  const loginBtn = (
    <button className="w-full rounded-full border border-[#333] bg-[rgba(31,31,31,0.62)] px-4 py-2 text-xs text-gray-300 transition-colors hover:border-white/50 hover:text-white sm:w-auto sm:px-3 sm:text-sm">
      <span className="inline-flex items-center gap-2">
        <LogIn className="h-3.5 w-3.5" />
        LogIn
      </span>
    </button>
  );

  const signupBtn = (
    <div className="group relative w-full sm:w-auto">
      <div className="pointer-events-none absolute inset-0 -m-2 hidden rounded-full bg-gray-100 opacity-40 blur-lg transition-all duration-300 ease-out group-hover:-m-3 group-hover:opacity-60 group-hover:blur-xl sm:block" />
      <button className="relative z-10 w-full rounded-full bg-gradient-to-br from-gray-100 to-gray-300 px-4 py-2 text-xs font-semibold text-black transition-all hover:from-gray-200 hover:to-gray-400 sm:w-auto sm:px-3 sm:text-sm">
        <span className="inline-flex items-center gap-2">
          <UserPlus className="h-3.5 w-3.5" />
          Signup
        </span>
      </button>
    </div>
  );

  return (
    <header
      className={cn(
        "fixed left-1/2 top-6 z-20 flex w-[calc(100%-2rem)] -translate-x-1/2 flex-col items-center border border-[#333] bg-[#1f1f1f57] px-6 py-3 backdrop-blur-sm transition-[border-radius] sm:w-auto",
        headerShapeClass,
      )}
    >
      <div className="flex w-full items-center justify-between gap-x-6 sm:gap-x-8">
        <Gamepad2 className="h-5 w-5 text-gray-200/90" />

        <nav className="hidden items-center space-x-4 text-sm sm:flex sm:space-x-6">
          {navLinks.map((link) => (
            <AnimatedNavLink key={link.href} href={link.href}>
              {link.label}
            </AnimatedNavLink>
          ))}
        </nav>

        <div className="hidden items-center gap-2 sm:flex sm:gap-3">
          {loginBtn}
          {signupBtn}
        </div>

        <button
          className="flex h-8 w-8 items-center justify-center text-gray-300 sm:hidden"
          onClick={() => setIsOpen((v) => !v)}
          aria-label={isOpen ? "Close Menu" : "Open Menu"}
        >
          {isOpen ? <X className="h-6 w-6" /> : <Menu className="h-6 w-6" />}
        </button>
      </div>

      <div
        className={cn(
          "flex w-full flex-col items-center overflow-hidden transition-all duration-300 ease-in-out sm:hidden",
          isOpen ? "max-h-[1000px] pt-4 opacity-100" : "pointer-events-none max-h-0 opacity-0",
        )}
      >
        <nav className="flex w-full flex-col items-center space-y-4 text-base">
          {navLinks.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="w-full text-center text-gray-300 transition-colors hover:text-white"
            >
              {link.label}
            </a>
          ))}
        </nav>
        <div className="mt-4 flex w-full flex-col items-center space-y-4">
          {loginBtn}
          {signupBtn}
        </div>
      </div>
    </header>
  );
}

const LegalCopy = () => (
  <p className="text-xs text-white/40">
    By signing up, you agree to the{" "}
    <Link href="#" className="text-white/40 underline transition-colors hover:text-white/60">
      MSA
    </Link>
    ,{" "}
    <Link href="#" className="text-white/40 underline transition-colors hover:text-white/60">
      Product Terms
    </Link>
    ,{" "}
    <Link href="#" className="text-white/40 underline transition-colors hover:text-white/60">
      Policies
    </Link>
    ,{" "}
    <Link href="#" className="text-white/40 underline transition-colors hover:text-white/60">
      Privacy Notice
    </Link>
    , and{" "}
    <Link href="#" className="text-white/40 underline transition-colors hover:text-white/60">
      Cookie Notice
    </Link>
    .
  </p>
);

export const SignInPage = ({ className }: SignInPageProps) => {
  const [email, setEmail] = useState("");
  const [step, setStep] = useState<"email" | "code" | "success">("email");
  const [code, setCode] = useState(["", "", "", "", "", ""]);
  const codeInputRefs = useRef<Array<HTMLInputElement | null>>([]);
  const [initialCanvasVisible, setInitialCanvasVisible] = useState(true);
  const [reverseCanvasVisible, setReverseCanvasVisible] = useState(false);
  const initialCanvasTimeoutRef = useRef<number | null>(null);
  const successStepTimeoutRef = useRef<number | null>(null);

  const clearStepTimeouts = () => {
    if (initialCanvasTimeoutRef.current !== null) {
      window.clearTimeout(initialCanvasTimeoutRef.current);
      initialCanvasTimeoutRef.current = null;
    }
    if (successStepTimeoutRef.current !== null) {
      window.clearTimeout(successStepTimeoutRef.current);
      successStepTimeoutRef.current = null;
    }
  };

  const completeCodeStep = () => {
    if (!code.every((digit) => digit.length === 1)) {
      return;
    }

    clearStepTimeouts();
    setReverseCanvasVisible(true);
    initialCanvasTimeoutRef.current = window.setTimeout(() => {
      setInitialCanvasVisible(false);
      initialCanvasTimeoutRef.current = null;
    }, 50);
    successStepTimeoutRef.current = window.setTimeout(() => {
      setStep("success");
      successStepTimeoutRef.current = null;
    }, 2000);
  };

  const handleEmailSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (email) setStep("code");
  };

  useEffect(() => {
    if (step !== "code") return;
    const id = setTimeout(() => codeInputRefs.current[0]?.focus(), 500);
    return () => clearTimeout(id);
  }, [step]);

  useEffect(() => () => clearStepTimeouts(), []);

  const handleCodeChange = (index: number, value: string) => {
    if (value.length > 1) return;

    const newCode = [...code];
    newCode[index] = value;
    setCode(newCode);

    if (value && index < 5) {
      codeInputRefs.current[index + 1]?.focus();
    }

    if (index === 5 && value && newCode.every((digit) => digit.length === 1)) {
      completeCodeStep();
    }
  };

  const handleBackClick = () => {
    clearStepTimeouts();
    setStep("email");
    setCode(["", "", "", "", "", ""]);
    setReverseCanvasVisible(false);
    setInitialCanvasVisible(true);
  };

  return (
    <div className={cn("relative flex min-h-screen w-full flex-col bg-black", className)}>
      <div className="absolute inset-0 z-0">
        {initialCanvasVisible && (
          <CanvasRevealEffect
            animationSpeed={3}
            containerClassName="absolute inset-0 bg-black"
            colors={[[255, 255, 255], [255, 255, 255]]}
            dotSize={6}
          />
        )}
        {reverseCanvasVisible && (
          <CanvasRevealEffect
            animationSpeed={4}
            containerClassName="absolute inset-0 bg-black"
            colors={[[255, 255, 255], [255, 255, 255]]}
            dotSize={6}
            reverse
          />
        )}
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,_rgba(0,0,0,1)_0%,_transparent_100%)]" />
        <div className="absolute left-0 right-0 top-0 h-1/3 bg-gradient-to-b from-black to-transparent" />
      </div>

      <div className="relative z-10 flex flex-1 flex-col">
        <MiniNavbar />

        <div className="flex flex-1 flex-col lg:flex-row">
          <div className="flex flex-1 flex-col items-center justify-center">
            <div className="mt-[150px] w-full max-w-sm">
              <AnimatePresence mode="wait">
                {step === "email" ? (
                  <motion.div
                    key="email-step"
                    initial={{ opacity: 0, x: -100 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: -100 }}
                    transition={{ duration: 0.4, ease: "easeOut" }}
                    className="space-y-6 text-center"
                  >
                    <div className="space-y-1">
                      <h1 className="text-[2.5rem] font-bold leading-[1.1] tracking-tight text-white">Welcome Developer</h1>
                      <p className="text-[1.8rem] font-light text-white/70">Your sign in component</p>
                    </div>

                    <div className="space-y-4">
                      <button className="flex w-full items-center justify-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-3 text-white backdrop-blur-[2px] transition-colors hover:bg-white/10">
                        <LogIn className="h-4 w-4" />
                        <span>Sign in with Google</span>
                      </button>

                      <div className="flex items-center gap-4">
                        <div className="h-px flex-1 bg-white/10" />
                        <span className="text-sm text-white/40">or</span>
                        <div className="h-px flex-1 bg-white/10" />
                      </div>

                      <form onSubmit={handleEmailSubmit}>
                        <div className="relative">
                          <input
                            type="email"
                            placeholder="info@gmail.com"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            className="w-full rounded-full border border-white/10 px-4 py-3 text-center text-white backdrop-blur-[1px] focus:border-white/30 focus:outline-none"
                            required
                          />
                          <button
                            type="submit"
                            className="group absolute right-1.5 top-1.5 flex h-9 w-9 items-center justify-center overflow-hidden rounded-full bg-white/10 text-white transition-colors hover:bg-white/20"
                          >
                            <span className="relative block h-full w-full overflow-hidden">
                              <span className="absolute inset-0 flex items-center justify-center transition-transform duration-300 group-hover:translate-x-full">
                                <ArrowRight className="h-4 w-4" />
                              </span>
                              <span className="absolute inset-0 flex -translate-x-full items-center justify-center transition-transform duration-300 group-hover:translate-x-0">
                                <ArrowRight className="h-4 w-4" />
                              </span>
                            </span>
                          </button>
                        </div>
                      </form>
                    </div>

                    <div className="pt-10">
                      <LegalCopy />
                    </div>
                  </motion.div>
                ) : step === "code" ? (
                  <motion.div
                    key="code-step"
                    initial={{ opacity: 0, x: 100 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: 100 }}
                    transition={{ duration: 0.4, ease: "easeOut" }}
                    className="space-y-6 text-center"
                  >
                    <div className="space-y-1">
                      <h1 className="text-[2.5rem] font-bold leading-[1.1] tracking-tight text-white">We sent you a code</h1>
                      <p className="text-[1.25rem] font-light text-white/50">Please enter it</p>
                    </div>

                    <div className="w-full">
                      <div className="relative rounded-full border border-white/10 bg-transparent px-5 py-4">
                        <div className="flex items-center justify-center">
                          {code.map((digit, i) => (
                            <div key={i} className="flex items-center">
                              <div className="relative">
                                <input
                                  ref={(el) => {
                                    codeInputRefs.current[i] = el;
                                  }}
                                  type="text"
                                  inputMode="numeric"
                                  pattern="[0-9]*"
                                  maxLength={1}
                                  value={digit}
                                  onChange={(e) => handleCodeChange(i, e.target.value)}
                                  onKeyDown={(e) => {
                                    if (e.key === "Backspace" && !code[i] && i > 0) {
                                      codeInputRefs.current[i - 1]?.focus();
                                    }
                                  }}
                                  className="w-8 appearance-none bg-transparent text-center text-xl text-white focus:outline-none"
                                  style={{ caretColor: "transparent" }}
                                />
                                {!digit && (
                                  <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
                                    <span className="text-xl text-white">0</span>
                                  </div>
                                )}
                              </div>
                              {i < 5 && <span className="text-xl text-white/20">|</span>}
                            </div>
                          ))}
                        </div>
                      </div>
                    </div>

                    <motion.p
                      className="inline-flex cursor-pointer items-center gap-2 text-sm text-white/50 transition-colors hover:text-white/70"
                      whileHover={{ scale: 1.02 }}
                      transition={{ duration: 0.2 }}
                    >
                      <RefreshCcw className="h-3.5 w-3.5" />
                      Resend code
                    </motion.p>

                    <div className="flex w-full gap-3">
                      <motion.button
                        onClick={handleBackClick}
                        className="w-[30%] rounded-full bg-white px-8 py-3 font-medium text-black transition-colors hover:bg-white/90"
                        whileHover={{ scale: 1.02 }}
                        whileTap={{ scale: 0.98 }}
                      >
                        Back
                      </motion.button>
                      <motion.button
                        onClick={completeCodeStep}
                        className={cn(
                          "flex-1 rounded-full border py-3 font-medium transition-all duration-300",
                          code.every((d) => d !== "")
                            ? "cursor-pointer border-transparent bg-white text-black hover:bg-white/90"
                            : "cursor-not-allowed border-white/10 bg-[#111] text-white/50",
                        )}
                        disabled={!code.every((d) => d !== "")}
                      >
                        Continue
                      </motion.button>
                    </div>

                    <div className="pt-16">
                      <LegalCopy />
                    </div>
                  </motion.div>
                ) : (
                  <motion.div
                    key="success-step"
                    initial={{ opacity: 0, y: 50 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.4, ease: "easeOut", delay: 0.3 }}
                    className="space-y-6 text-center"
                  >
                    <div className="space-y-1">
                      <h1 className="text-[2.5rem] font-bold leading-[1.1] tracking-tight text-white">You&apos;re in!</h1>
                      <p className="text-[1.25rem] font-light text-white/50">Welcome</p>
                    </div>

                    <motion.div
                      initial={{ scale: 0.8, opacity: 0 }}
                      animate={{ scale: 1, opacity: 1 }}
                      transition={{ duration: 0.5, delay: 0.5 }}
                      className="py-10"
                    >
                      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-gradient-to-br from-white to-white/70">
                        <Check className="h-8 w-8 text-black" />
                      </div>
                    </motion.div>

                    <motion.button
                      initial={{ opacity: 0 }}
                      animate={{ opacity: 1 }}
                      transition={{ delay: 1 }}
                      className="w-full rounded-full bg-white py-3 font-medium text-black transition-colors hover:bg-white/90"
                    >
                      Continue to Dashboard
                    </motion.button>
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </div>

          <aside className="relative hidden flex-1 items-end p-8 lg:flex">
            <div className="absolute inset-6 overflow-hidden rounded-3xl border border-white/15">
              <img
                src="https://images.unsplash.com/photo-1511512578047-dfb367046420?auto=format&fit=crop&w=1400&q=80"
                alt="Gaming setup background"
                className="h-full w-full object-cover opacity-65"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />
            </div>
            <div className="relative z-10 max-w-sm p-6 text-white">
              <p className="text-xs uppercase tracking-[0.28em] text-white/70">Community spotlight</p>
              <h2 className="mt-3 text-2xl font-semibold leading-tight">
                Build worlds, deploy updates, and ship faster with your player base.
              </h2>
              <p className="mt-3 text-sm text-white/80">
                This stock visual is served from Unsplash for rapid prototyping.
              </p>
            </div>
          </aside>
        </div>
      </div>
    </div>
  );
};
