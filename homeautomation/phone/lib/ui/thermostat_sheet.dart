import 'package:flutter/material.dart';

import '../controllers/thermostat_controller.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'thermostat_screen.dart';

/// Zakładki arkusza termostatu.
enum ThermostatTab { control, schedule, settings }

/// Arkusz termostatu z pulpitu (dotyk kafelka termostatu): Sterowanie, Harmonogram, Ustawienia - te same
/// ekrany co na ekranie termostatu, bez przechodzenia do niego. Harmonogram i ustawienia wymagają `config`.
Future<void> showThermostatSheet(
  BuildContext context,
  ThermostatController c, {
  ThermostatTab initial = ThermostatTab.control,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (ctx) => SizedBox(
    height: MediaQuery.sizeOf(ctx).height * 0.9,
    child: DefaultTabController(
      length: ThermostatTab.values.length,
      initialIndex: initial.index,
      child: ListenableBuilder(
        listenable: c,
        builder: (ctx, _) {
          final ready = c.state != null && c.config != null;
          Widget needs(String text) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(text, textAlign: TextAlign.center),
            ),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(c.config?.name ?? c.device.name, style: Theme.of(ctx).textTheme.titleLarge),
              ),
              const TabBar(
                tabs: [
                  Tab(key: Key('thermoTab-control'), text: 'Sterowanie'),
                  Tab(key: Key('thermoTab-schedule'), text: 'Harmonogram'),
                  Tab(key: Key('thermoTab-settings'), text: 'Ustawienia'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ThermostatControls(controller: c),
                    !ready
                        ? needs('Brak połączenia z termostatem.')
                        : !c.canConfig
                        ? needs('Harmonogram zmienia osoba z pełnym dostępem do termostatu.')
                        : ScheduleScreen(controller: c),
                    !ready
                        ? needs('Brak połączenia z termostatem.')
                        : !c.canConfig
                        ? needs('Ustawienia zmienia osoba z pełnym dostępem do termostatu.')
                        : SettingsScreen(controller: c),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  ),
);
