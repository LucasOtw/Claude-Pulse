import CoreLocation

/// Deuxième filet, plus solide que le son silencieux, pour qu'iOS n'endorme pas l'app
/// écran verrouillé : la localisation en arrière-plan, en précision très grossière
/// (antennes, pas de GPS). La position n'est ni stockée ni envoyée : seul compte le fait
/// que le service tourne. iOS affiche une petite pastille bleue en haut de l'écran.
final class LocationKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var session: CLBackgroundActivitySession?
    private var wanted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false // sinon iOS coupe quand le téléphone ne bouge pas
        manager.activityType = .other
    }

    /// À appeler au premier plan : iOS refuse de démarrer la localisation depuis l'arrière-plan.
    func start() {
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization() // suite dans locationManagerDidChangeAuthorization
        case .authorizedWhenInUse, .authorizedAlways: begin()
        default: break // refusée : le son silencieux reste seul
        }
    }

    func stop() {
        wanted = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        session?.invalidate()
        session = nil
    }

    private func begin() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if session == nil { session = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wanted else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: begin()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
