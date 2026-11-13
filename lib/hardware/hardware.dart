import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';

import '../printing/receipt_printer.dart';

/// Types d'afficheur client possibles.
const customerDisplayTypes = <String, String>{
  'none': 'Aucun',
  'screen': 'Second écran face à la cliente',
  'vfd': 'Petit afficheur 2 lignes (USB / COM)',
};

/// Réglages du matériel du poste de caisse, mémorisés sur ce PC.
class Hardware {
  static const _touchKey = 'hw_touch_mode';
  static const _drawerKey = 'hw_drawer_enabled';
  static const _drawerAutoKey = 'hw_drawer_auto';
  static const _displayKey = 'hw_customer_display';

  /// PC tactile : boutons et champs plus grands (appliqué à toute l'application).
  static final touchMode = ValueNotifier<bool>(false);

  static bool drawerEnabled = false;
  static bool drawerAutoOnCash = true;
  static String customerDisplay = 'none';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    touchMode.value = p.getBool(_touchKey) ?? false;
    drawerEnabled = p.getBool(_drawerKey) ?? false;
    drawerAutoOnCash = p.getBool(_drawerAutoKey) ?? true;
    customerDisplay = p.getString(_displayKey) ?? 'none';
  }

  static Future<void> setTouchMode(bool v) async {
    touchMode.value = v;
    await (await SharedPreferences.getInstance()).setBool(_touchKey, v);
  }

  static Future<void> setDrawerEnabled(bool v) async {
    drawerEnabled = v;
    await (await SharedPreferences.getInstance()).setBool(_drawerKey, v);
  }

  static Future<void> setDrawerAuto(bool v) async {
    drawerAutoOnCash = v;
    await (await SharedPreferences.getInstance()).setBool(_drawerAutoKey, v);
  }

  static Future<void> setCustomerDisplay(String v) async {
    customerDisplay = v;
    await (await SharedPreferences.getInstance()).setString(_displayKey, v);
  }

  /// Ouvre le tiroir-caisse branché sur l'imprimante de tickets (prise RJ11).
  /// Commande standard ESC/POS « ESC p 0 25 250 », envoyée en brut à l'imprimante.
  static Future<void> openDrawer() async {
    final name = await ReceiptPrinter.selectedName();
    if (name == null) {
      throw Exception('Choisissez d\'abord l\'imprimante de tickets dans Réglages > Matériels.');
    }
    RawPrinter.send(name, const [0x1B, 0x70, 0x00, 0x19, 0xFA]);
  }
}

/// Envoi d'octets bruts à une imprimante Windows (sans passer par le pilote graphique).
class RawPrinter {
  static void send(String printerName, List<int> bytes) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Disponible uniquement sous Windows.');
    }
    final pName = printerName.toNativeUtf16();
    final docName = 'Salon - tiroir'.toNativeUtf16();
    final dataType = 'RAW'.toNativeUtf16();
    final phPrinter = calloc<HANDLE>();
    final docInfo = calloc<DOC_INFO_1>();
    final written = calloc<Uint32>();
    final buffer = calloc<Uint8>(bytes.length);
    try {
      if (OpenPrinter(pName, phPrinter, nullptr) == 0) {
        throw Exception('Imprimante « $printerName » introuvable.');
      }
      final h = phPrinter.value;
      try {
        docInfo.ref
          ..pDocName = docName
          ..pOutputFile = nullptr
          ..pDatatype = dataType;
        if (StartDocPrinter(h, 1, docInfo) == 0) {
          throw Exception('Windows a refusé l\'envoi à l\'imprimante.');
        }
        StartPagePrinter(h);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final ok = WritePrinter(h, buffer, bytes.length, written);
        EndPagePrinter(h);
        EndDocPrinter(h);
        if (ok == 0) throw Exception('L\'imprimante n\'a pas reçu la commande.');
      } finally {
        ClosePrinter(h);
      }
    } finally {
      free(pName);
      free(docName);
      free(dataType);
      free(phPrinter);
      free(docInfo);
      free(written);
      free(buffer);
    }
  }
}
