const std = @import("std");
const sdl = @import("SDLimport.zig");
pub const list = std.ArrayList;

// Main parameters
const refreshrate = 20; // [ms]
const gravity = 160.0; // [pix/s²]
const minHeight = 0.45;
const maxHeight = 0.95;
const probrocket = 1;
const maxHorizV = 0.25;
const minPartV = 1.0;
const maxPartV = 9.0;
const partLifespan = 270;
const partFriction = 0.97;
const nParticles = 300;

// Allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
// Randomizer
var prgn: std.Random.DefaultPrng = undefined;
// Calculated parameters
var height: u32 = undefined;
var width: u32 = undefined;
var vMin: f32 = undefined;
var vMax: f32 = undefined;
var renderer: *sdl.SDL_Renderer = undefined;
const refr: comptime_float = @as(f32, @floatFromInt(refreshrate)) / 1000.0;
const grav: comptime_float = gravity * refr * refr;

fn ColorCode(hue: f32, code: f32) u8 {
	// Saturated colors at maximum brightness
	// codes: red = 5.0, green = 3.0, blue = 1.0
    const k = @mod((code + 6.0 * hue), 6.0);
    const res = 1.0 - @max(0.0, @min(1.0, @min(k, 4.0 - k)));
    return @as(u8, @intFromFloat(255.0 * res));
}

const Rocket = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    pub fn init() Rocket {
        return .{
            .x = @floatFromInt(prgn.random().uintLessThan(u32, width)),
            .y = @floatFromInt(height - 1),
            .vx = (prgn.random().float(f32) * 2.0 - 1.0) * maxHorizV,
            .vy = -(prgn.random().float(f32) * (vMax - vMin) + vMin),
        };
    }
    pub fn update(self: *Rocket) bool {
        self.vy += grav;
        self.x += self.vx;
        self.y += self.vy;
        return self.vy >= 0.0;
    }
    pub fn render(self: Rocket) void {
        _ = sdl.SDL_RenderDrawPointF(renderer, self.x, self.y);
    }
};

const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: u16,
    channelR: u8,
    channelG: u8,
    channelB: u8,
    pub fn init(x: f32, y: f32, hue: f32) Particle {
        const angle: f32 = prgn.random().float(f32) * std.math.tau;
        const v = minPartV + prgn.random().float(f32) * (maxPartV - minPartV);
        return .{
            .x = x,
            .y = y,
            .vx = v * @cos(angle),
            .vy = v * @sin(angle),
            .life = partLifespan,
            .channelR = ColorCode(hue, 5.0),
            .channelG = ColorCode(hue, 3.0),
            .channelB = ColorCode(hue, 1.0),
        };
    }
    pub fn update(self: *Particle) bool {
        self.vy += grav;
        self.vx *= partFriction;
        self.vy *= partFriction;
        self.x += self.vx;
        self.y += self.vy;
        self.life -= 1;
        return self.life == 0;
    }
    pub fn render(self: Particle) void {
        _ = sdl.SDL_SetRenderDrawColor(
            renderer,
            self.channelR,
            self.channelG,
            self.channelB,
            @min(255, self.life),
        );
        _ = sdl.SDL_RenderDrawPointF(renderer, self.x, self.y);
    }
};

const FireWorks = struct {
    rockets: list(Rocket),
    particles: list(Particle),
    removelist: list(usize),
    rocketrate: f32,
    pub fn init() FireWorks {
        return .{
            .rocketrate = probrocket * refr,
            .rockets = list(Rocket).init(allocator),
            .particles = list(Particle).init(allocator),
            .removelist = list(usize).init(allocator),
        };
    }
    pub fn deinit(self: FireWorks) void {
        self.rockets.deinit();
        self.particles.deinit();
        self.removelist.deinit();
    }
    pub fn update(self: *FireWorks) !void {
        for (self.rockets.items, 0..) |*rocket, index| {
            if (rocket.update()) { // explosion
                try self.removelist.append(index);
                const hue: f32 = prgn.random().float(f32);
                for (0..nParticles) |_| try self.particles.append(Particle.init(rocket.x, rocket.y, hue));
            }
        }
        while(self.removelist.popOrNull()) |index| _ = self.rockets.swapRemove(index);
        for (self.particles.items, 0..) |*particle, index| {
            if (particle.update()) try self.removelist.append(index);
        }
        while(self.removelist.popOrNull()) |index| _ = self.particles.swapRemove(index);
        // Launch a new rocket?
        if (prgn.random().float(f32) < self.rocketrate) {
            try self.rockets.append(Rocket.init());
        }
    }
    pub fn render(self: FireWorks) void {
        _ = sdl.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255);
        for (self.rockets.items) |rocket| rocket.render();
        for (self.particles.items) |particle| particle.render();
    }
};

pub fn main() !void {
    // initialise Randimizer
    var seed: u64 = undefined;
    try std.posix.getrandom(std.mem.asBytes(&seed));
    prgn = std.Random.DefaultPrng.init(seed);
    // initialise SDL
    if (sdl.SDL_Init(sdl.SDL_INIT_TIMER) != 0) {
        std.debug.print("SDL initialisation error: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_initialisationerror;
    }
    defer sdl.SDL_Quit();
    const window: *sdl.SDL_Window = sdl.SDL_CreateWindow(
        "Game window",
        0,
        0,
        1600,
        900,
        sdl.SDL_WINDOW_FULLSCREEN_DESKTOP,
    ) orelse {
        std.debug.print("SDL window creation failed: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_windowcreationfailed;
    };
    defer sdl.SDL_DestroyWindow(window);
    _ = sdl.SDL_GetWindowSize(window, @ptrCast(&width), @ptrCast(&height));
    renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED) orelse {
        std.debug.print("SDL renderer creation failed: {s}\n", .{sdl.SDL_GetError()});
        return error.sdl_renderercreationfailed;
    };
    defer sdl.SDL_DestroyRenderer(renderer);
    _ = sdl.SDL_SetRenderDrawBlendMode(renderer, sdl.SDL_BLENDMODE_BLEND);
    // Initialise constants
    vMin = @sqrt(2.0 * grav * minHeight * @as(f32, @floatFromInt(height)));
    vMax = @sqrt(2.0 * grav * maxHeight * @as(f32, @floatFromInt(height)));
    // Initialise fireworks
    var fireworks = FireWorks.init();
    defer fireworks.deinit();

    // Hide mouse
    _ = sdl.SDL_ShowCursor(sdl.SDL_DISABLE);

    var timer = try std.time.Timer.start();
    var stoploop = false;
    var event: sdl.SDL_Event = undefined;
    while (!stoploop) {
        timer.reset();
        _ = sdl.SDL_RenderPresent(renderer);
        _ = sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 27);
        _ = sdl.SDL_RenderFillRect(renderer, null);
        fireworks.render();
        try fireworks.update();
        while (sdl.SDL_PollEvent(&event) != 0) {
            if (event.type == sdl.SDL_KEYDOWN) stoploop = true;
        }
        const lap: u32 = @intCast(timer.read() / 1_000_000);
        if (lap < refreshrate) sdl.SDL_Delay(refreshrate - lap);
    }
}
