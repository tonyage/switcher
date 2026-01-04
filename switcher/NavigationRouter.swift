//
//  NavigationRouter.swift
//  switcher
//
//  Created by Tony Do on 1/4/26.
//

import SwiftUI

enum Screen {
    case home
    case settings
}

/// Manage app navigation/routing myself since themeing NavigationStack appears
/// to not work.
@Observable
class NavigationRouter {
    var paths = NavigationPath()
    
    @MainActor
    @ViewBuilder
    func navigate(to screen: Screen) -> some View {
        switch screen {
            case .home:
                ContentView()
            case .settings:
                Settings()
        }
    }
    
    func push(_ screen: Screen) {
        paths.append(screen)
    }
    
    func pop() {
        paths.removeLast()
    }
    
    func popToRoot() {
        paths.removeLast(paths.count)
    }
}
