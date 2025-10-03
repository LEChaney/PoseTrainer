import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'wgpu_probe_host.dart';
import '../services/wgpu_probe.dart';

/// Simple host widget for the Rust wgpu-probe.
/// Web: renders a container div with id 'wgpu-probe-container' that the WASM code appends a canvas into.
/// Other platforms: shows a placeholder for now.
class WgpuProbeView extends StatefulWidget {
  const WgpuProbeView({super.key, this.width = 640, this.height = 360});
  final double width;
  final double height;

  @override
  State<WgpuProbeView> createState() => _WgpuProbeViewState();
}

class _WgpuProbeViewState extends State<WgpuProbeView> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Register platform view BEFORE any build where HtmlElementView is used.
      ensureWebHostRegistered('wgpu-probe-container');
      // Fire-and-forget module load; errors will surface in DevTools.
      WgpuProbeService.ensureLoaded();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: _WgpuWebHost(),
      );
    }
    return Container(
      alignment: Alignment.center,
      width: widget.width,
      height: widget.height,
      color: const Color(0xFF0B0B10),
      child: const Text('WGPU probe placeholder (native hookup TBD)'),
    );
  }
}

class _WgpuWebHost extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Use a HtmlElementView via platform views for web by rendering a div with the expected id.
    // We render a regular div via HtmlElementView to give the Rust code a known container.
    return const _WebDivHost(elementId: 'wgpu-probe-container');
  }
}

class _WebDivHost extends StatelessWidget {
  final String elementId;
  const _WebDivHost({required this.elementId});

  @override
  Widget build(BuildContext context) {
    // This relies on index.html including a div with the same id or on our Rust code creating it.
    // For simplicity, we ensure the element exists by rendering a HtmlElementView bound to it.
    // ignore: undefined_prefixed_name
    return HtmlElementView(viewType: elementId);
  }
}
