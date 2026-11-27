// Forces the local Vulkan loader to discover and instantiate VK_LAYER_pyroveil.
// Build for the same ABI the games use, then run it under the same environment.
//
// A layer that is discovered but not loadable shows up as
// VK_ERROR_LAYER_NOT_PRESENT (-7); a correct build returns VK_SUCCESS.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>

struct AppInfo {
	int32_t sType; const void *pNext; const char *appName; uint32_t appVersion;
	const char *engineName; uint32_t engineVersion; uint32_t apiVersion;
};
struct InstanceCI {
	int32_t sType; const void *pNext; uint32_t flags; const AppInfo *app;
	uint32_t layerCount; const char *const *layers;
	uint32_t extCount; const char *const *exts;
};
struct LayerProps { char name[256]; uint32_t specVersion; uint32_t implVersion; char desc[256]; };

typedef int32_t (*EnumerateLayers)(uint32_t *, LayerProps *);
typedef int32_t (*CreateInstance)(const InstanceCI *, const void *, void **);

int main() {
	void *loader = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_GLOBAL);
	if (!loader) { printf("dlopen libvulkan.so.1 failed: %s\n", dlerror()); return 1; }

	auto enumLayers = (EnumerateLayers) dlsym(loader, "vkEnumerateInstanceLayerProperties");
	auto createInstance = (CreateInstance) dlsym(loader, "vkCreateInstance");
	if (!enumLayers || !createInstance) { printf("dlsym of loader entry points failed\n"); return 1; }

	uint32_t count = 0;
	enumLayers(&count, nullptr);
	LayerProps *props = new LayerProps[count];
	enumLayers(&count, props);

	bool discovered = false;
	printf("loader sees %u layers:\n", count);
	for (uint32_t i = 0; i < count; i++) {
		printf("   %s\n", props[i].name);
		if (!strcmp(props[i].name, "VK_LAYER_pyroveil")) discovered = true;
	}
	printf("DISCOVERED VK_LAYER_pyroveil: %s\n", discovered ? "YES" : "NO");

	AppInfo app{};
	app.sType = 0; app.apiVersion = (1u << 22) | (4u << 12);
	app.appName = "pyroveil_probe"; app.engineName = "pyroveil_probe";
	const char *names[] = { "VK_LAYER_pyroveil" };
	InstanceCI ci{};
	ci.sType = 1; ci.app = &app; ci.layerCount = 1; ci.layers = names;

	void *instance = nullptr;
	int32_t r = createInstance(&ci, nullptr, &instance);
	printf("vkCreateInstance with VK_LAYER_pyroveil enabled = %d", r);
	if (r == 0) printf(" (VK_SUCCESS - layer loaded)\n");
	else if (r == -7) printf(" (VK_ERROR_LAYER_NOT_PRESENT - not discoverable/loadable)\n");
	else if (r == -9) printf(" (VK_ERROR_INCOMPATIBLE_DRIVER - ICD issue, layer load still attempted)\n");
	else printf("\n");

	delete[] props;
	return discovered ? 0 : 1;
}
