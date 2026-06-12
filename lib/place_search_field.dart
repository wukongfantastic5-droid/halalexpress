import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PlaceSearchField extends StatefulWidget {
  final TextEditingController controller;
  final Function(String, double, double) onSelected;

  const PlaceSearchField({
    super.key,
    required this.controller,
    required this.onSelected,
  });

  @override
  State<PlaceSearchField> createState() =>
      _PlaceSearchFieldState();
}

class _PlaceSearchFieldState
    extends State<PlaceSearchField> {

  List places = [];

  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // 🔴 FORCE CLOSE OVERLAY
  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 🔵 SEARCH FUNCTION (FULLY SAFE)
  Future<void> search(String value) async {

    final text = value.trim();

    // ❗ HARD RULE: EMPTY = NO POPUP
    if (text.isEmpty) {
      places = [];
      _closeOverlay();
      setState(() {});
      return;
    }

    try {

      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search"
        "?q=$text&format=json&limit=5",
      );

      final res = await http.get(
        url,
        headers: {
          "User-Agent": "gombak_runner"
        },
      );

      final data = jsonDecode(res.body);

      places = data;

      // ❗ DOUBLE CHECK BEFORE SHOWING
      if (text.isEmpty || places.isEmpty) {
        _closeOverlay();
        setState(() {});
        return;
      }

      setState(() {});
      _showOverlay();

    } catch (e) {
      print("SEARCH ERROR: $e");
      _closeOverlay();
    }
  }

  // 🔵 SHOW OVERLAY
  void _showOverlay() {

    _closeOverlay();

    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: MediaQuery.of(context).size.width - 32,

          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 60),

            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),

              child: Container(
                height: 200,
                color: Colors.white,

                child: ListView.builder(
                  itemCount: places.length,

                  itemBuilder: (context, index) {

                    final p = places[index];

                    return ListTile(
                      leading: const Icon(
                        Icons.location_on,
                        color: Colors.blue,
                      ),

                      title: Text(
                        p["display_name"],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      onTap: () {

                        widget.controller.text =
                            p["display_name"];

                        widget.onSelected(
                          p["display_name"],
                          double.parse(p["lat"]),
                          double.parse(p["lon"]),
                        );

                        places = [];
                        _closeOverlay();

                        FocusScope.of(context).unfocus();
                        setState(() {});
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return CompositedTransformTarget(
      link: _layerLink,

      child: TextField(
        controller: widget.controller,

        onChanged: (value) {

          // 🔴 HARD GUARD: immediate close if empty
          if (value.trim().isEmpty) {
            places = [];
            _closeOverlay();
            setState(() {});
            return;
          }

          search(value);
        },

        decoration: InputDecoration(
          labelText: "Mencari alamat lokasi",
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}