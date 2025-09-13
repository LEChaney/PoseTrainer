import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/pose.dart';
import 'services/timer_service.dart';
import 'services/pose_sequence_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const PoseCoachApp());
}

class PoseCoachApp extends StatelessWidget {
  const PoseCoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TimerService()),
        ChangeNotifierProvider(
          create: (_) =>
              PoseSequenceService(poses: Pose.sampleSet(), cycles: 1),
        ),
      ],
      child: MaterialApp(
        title: 'PoseCoach',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
